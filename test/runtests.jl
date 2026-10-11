using ADES
using Dates
using Test
const Tables = ADES.Tables

const DATA = joinpath(@__DIR__, "data")

@testset "ADES.jl" begin

@testset "PSV reading" begin
    d = read_ades(joinpath(DATA, "example.psv"))
    @test d.version == "2022"
    @test length(d.blocks) == 1
    @test length(d) == 3

    ctx = d.blocks[1].context
    @test ctx["observatory"]["mpcCode"] == "J95"
    @test getall(ctx["observers"], "name") == ["A. Observer", "B. Helper"]
    @test ctx["fundingSource"].value == "Example Foundation"
    @test haskey(ctx, "telescope") && !haskey(ctx, "software")
    @test_throws KeyError ctx["software"]

    o1, o2, o3 = observations(d)
    @test o1.kind === :optical
    @test o1.permID == "433"
    @test designation(o1) == "433"
    @test designation(o2) == "2024 AB12"
    @test designation(o3) == "XY12345"
    @test o1.ra === 120.1234567
    @test o1.dec === 20.123456
    @test rawvalue(o1, :dec) == "+20.123456"
    @test o1.obsTime == DateTime(2024, 1, 15, 21, 3, 12, 250)
    @test o1.provID === missing
    @test !haskey(o1, :provID)
    @test o2.disc == "*"
    @test o2.remarks == "fast mover"
    @test o3.rmsRA === missing
    @test julian_date(o3) ≈ datetime2julian(DateTime(2024, 1, 15, 21, 20)) + 0.123456 / 86400 atol = 1e-9
end

@testset "XML reading" begin
    d = read_ades(joinpath(DATA, "example.xml"))
    @test d.version == "2022"
    @test length(d.blocks) == 2
    @test d.blocks[2].context === nothing
    @test [o.kind for o in d] == [:optical, :occultation, :radar]

    ctx = d.blocks[1].context
    @test ctx["submitter"]["institution"] == "Example University"

    opt, occ, rad = observations(d)
    # leap second rolls over into the next year
    @test opt.obsTime == DateTime(2024, 1, 1, 0, 0, 0, 500)
    @test occursin("<myTag a=\"1\">custom</myTag>", rawvalue(opt, :localUse))
    @test occ.ctr === 399
    @test occ.rmsCorr === -0.874
    @test rawvalue(occ, :deltaRA) == "0.0000"
    @test rad.delay === 1234.5678901234
    @test rad.trx == "253"
end

@testset "round trips" begin
    for f in ("example.psv", "example.xml")
        d = read_ades(joinpath(DATA, f))
        obs = observations(d)

        dx = parse_xml(xml_string(d))
        @test observations(dx) == obs
        @test dx.version == d.version
        @test [b.context === nothing for b in dx.blocks] == [b.context === nothing for b in d.blocks]
        c1, c2 = d.blocks[1].context, dx.blocks[1].context
        @test [(s.name, s.value, s.entries) for s in c1.sections] ==
              [(s.name, s.value, s.entries) for s in c2.sections]

        # PSV cannot hold localUse
        strip_local(o) = (o = copy(o); o.localUse = missing; o)
        for align in (true, false)
            dp = parse_psv(psv_string(d; align=align))
            @test observations(dp) == strip_local.(obs)
        end

        # file-based writing and format detection
        mktempdir() do dir
            for ext in (".xml", ".psv")
                path = joinpath(dir, "out" * ext)
                write_ades(path, d)
                @test startswith(read(path, String), ext == ".xml" ? "<?xml" : "# version")
                @test observations(read_ades(path)) == (ext == ".xml" ? obs : strip_local.(obs))
            end
            @test_throws ArgumentError write_ades(joinpath(dir, "x"), d; format=:json)
        end
    end
end

@testset "XML element order" begin
    o = Observation(:optical; astCat="Gaia3", dec=-1.5, ra=10.25, obsTime="2024-01-01T00:00:00Z",
                    stn="568", mode="CCD", provID="2024 AA")
    xml = xml_string(ADESData(nothing, [o]))
    pos = [findfirst("<$k>", xml)[1] for k in (:provID, :mode, :stn, :obsTime, :ra, :dec, :astCat)]
    @test issorted(pos)
end

@testset "PSV structure" begin
    psv = """
    # version=2022
    # observatory
    ! mpcCode 568
    permID|mode|stn|obsTime|ra|dec|astCat
    1|CCD|568|2024-01-01T00:00:00Z|1.0|2.0|Gaia3
    permID|mode|stn|obsTime|raStar|decStar|deltaRA|deltaDec|astCat
    2|OCC|568|2024-01-01T00:00:00Z|1.0|2.0|0.1|0.2|Gaia3
    # observatory
    ! mpcCode 309
    permID|mode|stn|obsTime|ra|dec|astCat|
    3|CCD|309|2024-01-02T00:00:00Z|3.0|4.0|Gaia3|
    """
    d = parse_ades(psv)
    @test length(d.blocks) == 2
    @test [o.kind for o in d.blocks[1].observations] == [:optical, :occultation]
    @test d.blocks[2].context["observatory"]["mpcCode"] == "309"
    @test d.blocks[2].observations[1].dec == 4.0

    @test_throws ArgumentError parse_psv("1|2|3\n")
    @test_throws ArgumentError parse_psv("permID|stn\n1|568|x\n")
    @test_throws ArgumentError parse_psv("! name X\n")
end

@testset "constructing observations" begin
    o = Observation(:optical; permID=433, mode="CCD", stn="J95",
                    obsTime=DateTime(2024, 3, 1, 12, 30, 15, 120), ra=150.5, dec=-2.25,
                    astCat="Gaia3E", mag=missing)
    @test rawvalue(o, :permID) == "433"
    @test rawvalue(o, :obsTime) == "2024-03-01T12:30:15.120Z"
    @test !haskey(o, :mag)
    o.mag = 17.25
    @test o.mag === 17.25
    o[:band] = "V"
    @test o[:band] == "V"
    o.mag = missing
    @test !haskey(o, :mag)
    o.rmsRA = 1.5e-7
    @test rawvalue(o, :rmsRA) == "0.00000015"
    o.pos1 = -1.25e20
    @test rawvalue(o, :pos1) == "-125000000000000000000"
    @test_throws ArgumentError (o.ra = NaN)
    @test_throws ArgumentError Observation(:spectral)
    @test_throws ArgumentError (o.kind = :radar)
    @test :ra in propertynames(o)
end

@testset "obstable" begin
    d = read_ades(joinpath(DATA, "example.psv"))
    t = obstable(d)
    @test t.kind == [:optical, :optical, :optical]
    @test t.ra == [120.1234567, 121.0000001, 122.5]
    @test eltype(t.ra) == Union{Missing,Float64}
    @test eltype(t.obsTime) == Union{Missing,DateTime}
    @test isequal(t.mag, [11.2, 19.5, missing])
    @test keys(t)[1:4] == (:kind, :permID, :provID, :trkSub)
    @test obstable(d; raw=true).dec == ["+20.123456", "-05.500001", "-5.4"]

    @test Tables.istable(d)
    @test Tables.columns(d).ra == t.ra
    @test length(Tables.rowtable(d)) == 3
end

@testset "validate" begin
    @test isempty(validate(read_ades(joinpath(DATA, "example.psv"))))
    @test isempty(validate(read_ades(joinpath(DATA, "example.xml")); submission=false))
    @test validate(read_ades(joinpath(DATA, "example.xml"))) == ["block 2: no obsContext"]

    bad = Observation(:optical; trkSub="TOOLONGID", mode="CCD", stn="J9", obsTime="2024-13-01",
                      ra=360.0, dec=-91.0, rmsCorr=1.0, xObs=1.0)
    p = validate(ADESData(nothing, [bad]; version="1999"); submission=false)
    has(s) = any(x -> occursin(s, x), p)
    @test has("unknown ADES version")
    @test has("missing required element astCat")
    @test has("trkSub = \"TOOLONGID\" is longer than 8")
    @test has("stn = \"J9\" must have 3 or 4")
    @test has("obsTime = \"2024-13-01\" is not a valid")
    @test has("ra = 360.0 outside")
    @test has("dec = -91.0 outside")
    @test has("rmsCorr = 1.0 outside")
    @test has("element xObs is not allowed")

    noid = Observation(:optical; mode="CCD", stn="568", obsTime="2024-01-01T00:00:00Z",
                       ra=1.0, dec=1.0, astCat="Gaia3", pos1=1.0, remarks="a|b")
    p = validate(ADESData(ObsContext(), [noid]))
    has2(s) = any(x -> occursin(s, x), p)
    @test has2("no identifier")
    @test has2("location group incomplete: missing sys")
    @test has2("remarks contains '|'")
    @test has2("obsContext lacks observatory/mpcCode")
end

@testset "display" begin
    d = read_ades(joinpath(DATA, "example.xml"))
    @test occursin("3 observations", sprint(show, d))
    @test occursin("ObsBlock(observatory=568", sprint(show, MIME"text/plain"(), d))
    o = first(d)
    @test startswith(sprint(show, o), "Observation(:optical, provID=\"2023 XY1\"")
    @test occursin("astCat", sprint(show, MIME"text/plain"(), o))
    @test occursin("submitter", sprint(show, MIME"text/plain"(), d.blocks[1].context))
end

end
