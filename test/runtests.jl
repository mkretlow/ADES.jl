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
        # blocks mixing record kinds are split, since obsData may hold only one kind
        @test count(b -> b.context === nothing, dx.blocks) == count(b -> b.context === nothing, d.blocks)
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

@testset "designations" begin
    # (packed, permID, provID, trkSub); cases from the IAU-ADES packUtil test suite
    cases = [
        ("00001       ", "1", nothing, nothing),
        ("z9999       ", "619999", nothing, nothing),
        ("~0000       ", "620000", nothing, nothing),
        ("C1234K14A00A", "121234", "2014 AA", nothing),
        ("     K14Aa0A", nothing, "2014 AA360", nothing),
        ("     K14Az9Q", nothing, "2014 AQ619", nothing),
        ("     _QC0aEM", nothing, "2026 CZ6190", nothing),
        ("01234T3S1438", "1234", "1438 T-3", nothing),
        ("07968J96N020", "7968", "A/1996 N2", nothing),
        ("    AJ96N020", nothing, "A/1996 N2", nothing),
        ("     I98V00F", nothing, "1898 VF", nothing),
        ("     A00001X", nothing, nothing, "A00001X"),
        ("     K00001X", nothing, nothing, "K00001X"),
        ("     PLS2a10", nothing, nothing, "PLS2a10"),
        ("0073P       ", "73P", nothing, nothing),
        ("    CK88AA30", nothing, "C/2088 A103", nothing),
        ("    PJ98Q54P", nothing, "P/1998 QP54", nothing),
        ("    CK33L89c", nothing, "C/2033 L89-C", nothing),
        ("0141PJ94P01a", "141P-A", "P/1994 P1-A", nothing),
        ("0073P     af", "73P-AF", nothing, nothing),
        ("0073P      g", "73P-G", nothing, nothing),
        ("J001SG10J010", "Jupiter 1", "S/1610 J 1", nothing),
        ("    SK10JB10", nothing, "S/2010 J 111", nothing),
    ]
    for (packed, perm, prov, trk) in cases
        @test unpack_designation(packed) == (perm, prov, trk)
        @test pack_designation(perm, prov, trk) == packed
    end
    for bad in ("            ", "00000       ", "0000P       ", "1234C       ", "U000S       ",
                "K221S       ", "_0000       ", "     A00 01 ", "0a001K14A00A")
        @test_throws ArgumentError unpack_designation(bad)
    end
    for ids in (("0", nothing, nothing), ("(45) 1", nothing, nothing), ("12345P", nothing, nothing),
                ("1", "P/1994 P1-A", nothing), ("141P-C", "P/1994 P1-A", nothing),
                (nothing, "568 T-1", nothing), (nothing, "2014 AA620", nothing),
                (nothing, "1700 AA", nothing), (nothing, "2001 IA", nothing),
                (nothing, "P/1998 QP54-A", nothing), (nothing, "S/2001 N 0", nothing),
                (nothing, nothing, "A1234567"), (nothing, nothing, "Ab3%xx"), (nothing, nothing, nothing))
        @test_throws ArgumentError pack_designation(ids...)
    end
    # a trkSub is not written when there is a permanent or provisional designation
    @test pack_designation("433", missing, "abc") == "00433       "
end

@testset "MPC 80-column" begin
    path = joinpath(DATA, "example.obs")
    txt = read(path, String)
    datalines(s) = filter(l -> length(l) == 80, split(s, r"\r?\n"))

    d = read_ades(path)
    @test d isa ADESData
    @test read_mpc80(path) == d || observations(read_mpc80(path)) == observations(d)
    @test length(d.blocks) == 2
    @test length(d) == 9
    @test [o.kind for o in d] == [fill(:optical, 8); :radar]

    ctx = d.blocks[1].context
    @test ctx["observatory"]["mpcCode"] == "Z80"
    @test ctx["submitter"]["name"] == "A. Observer"
    @test ctx["submitter"]["institution"] == "Example Observatory, Somewhere"
    @test getall(ctx["observers"], "name") == ["A. Observer", "B. Helper"]
    @test ctx["telescope"]["aperture"] == "0.41"
    @test ctx["telescope"]["fRatio"] == "6.3"
    @test ctx["telescope"]["design"] == "Schmidt-Cassegrain"
    @test getall(ctx["comment"], "line") ==
          ["NET Gaia-DR3", "ACK Batch 001", "Positions are made up for testing."]

    o1, o2, o3, o4, o5, o6, o7, o8, rad = observations(d)
    @test o1.permID == "433"
    @test rawvalue(o1, :obsTime) == "2024-01-15T21:03:11.808Z"
    @test rawvalue(o1, :precTime) == "10"
    @test rawvalue(o1, :ra) == "120.12346"
    @test rawvalue(o1, :precRA) == "0.01"
    @test rawvalue(o1, :dec) == "20.12344"
    @test rawvalue(o1, :precDec) == "0.1"
    @test o1.astCat == "Gaia3E"
    @test o1.subFmt == "M92"
    @test o2.provID == "2024 AB12"
    @test o2.disc == "*"
    @test o2.notes == "K"            # Z80 does not use program codes
    @test o2.ref == "MPS 1229401"
    @test o2.dec === -5.5
    @test rawvalue(o2, :ra) == "121.000000"
    @test o3.trkSub == "ABC1234" && o3.mode == "CMO" && o3.astCat == "UNK"
    @test o4.deprecated == "X" && o4.mag === missing && o4.band === missing
    @test o5.subFrm == "B1950.0"
    @test o6.prog == "01"            # F51 uses program codes
    @test !haskey(o6, :notes)
    @test (o7.sys, o7.ctr, o7.pos1) == ("ICRF_KM", 399, -5634.1734)
    @test (o8.sys, rawvalue(o8, :pos2), o8.pos3) == ("WGS84", "+43.7900", 1200.0)
    @test rad.delay === 1.508853604
    @test rawvalue(rad, :rmsDelay) == "15"
    @test (rad.trx, rad.rcv, rad.com, rad.frq) == ("251", "251", 0, 2380.0)
    @test rawvalue(rad, :obsTime) == "1975-01-22T04:30:00Z"

    # 80 -> ADES -> 80 and 80 -> ADES XML -> 80 reproduce the data lines
    @test datalines(mpc80_string(d)) == datalines(txt)
    @test datalines(mpc80_string(parse_xml(xml_string(d)))) == datalines(txt)
    @test datalines(mpc80_string(parse_psv(psv_string(d)))) == datalines(txt)
    mktempdir() do dir
        p = joinpath(dir, "out.obs")
        write_ades(p, d)
        @test datalines(read(p, String)) == datalines(txt)
    end

    # radar records with delay and Doppler are split
    r2 = parse_mpc80("""
        00433         R1975 01 22.187500    15088536040-        130000 23800251 AJ102251
        00433         r1975 01 22.187500S        150000         200000      251 AJ102251
        """)
    a, b = observations(r2)
    @test haskey(a, :delay) && !haskey(a, :doppler)
    @test b.doppler === -13.0 && b.rmsDoppler === 20.0 && !haskey(b, :delay)

    # submission mode drops elements the submission schema does not allow
    s = read_mpc80(path; submission=true)
    @test !any(o -> any(k -> haskey(o, k), (:subFmt, :precRA, :deprecated, :prog, :ref)), s)

    # obsData holds one record kind, so the optical/radar block becomes two obsBlocks
    @test count("<obsBlock>", xml_string(d)) == 3

    # ADES without precision elements: precision follows the digits given
    o = Observation(:optical; provID="2024 AB12", mode="CCD", stn="J95",
                    obsTime="2024-01-15T21:03:11.808Z", ra="120.123457", dec="-20.12345",
                    astCat="Gaia3E", mag="19.531", band="Gr", prog="01")
    line = mpc80_string(ADESData(nothing, [o]))
    @test line == "     K24A12B 1C2024 01 15.87722008 00 29.630-20 07 24.4          19.53GX     J95\n"
    @test length(chomp(line)) == 80

    @test_throws ArgumentError parse_mpc80("00433         C2024 01 15.87722 08 00 29.63 +20 07 24.4          11.2 GX     Z80 extra")
    @test_throws ArgumentError parse_mpc80("     K10A00A  s2010 01 08.94792 1 - 5634.1734 - 2466.2657 - 3038.3924        C51")
    @test_throws ArgumentError parse_mpc80("     K10A00A  S2010 01 08.94792 21 33 37.97 -01 50 47.6          19.5 V      C51")
    @test_throws ArgumentError mpc80_string(read_ades(joinpath(DATA, "example.xml")))
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
