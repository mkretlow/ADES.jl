# Conversion between ADES and the MPC 80-column format ("MPC1992", obs80).
# Format: https://www.minorplanetcenter.net/iau/info/OpticalObs.html,
#         https://www.minorplanetcenter.net/iau/info/RadarObs.html
# Conventions follow the IAU-ADES reference converters (mpc80coltoxml.py, xmltompc80col.py).

# Column 15 code => ADES mode
const _MODE_OF_CODE = Dict(
    'P' => "PHo", ' ' => "PHO", 'e' => "ENC", 'C' => "CCD", 'B' => "CMO", 'T' => "MER",
    'M' => "MIC", 'c' => "ccd", 'E' => "OCC", 'O' => "OFF", 'H' => "PMT", 'N' => "NOR",
    'n' => "VID",
)
const _CODE_OF_MODE = Dict(v => k for (k, v) in _MODE_OF_CODE)

# Column 72 catalogue code => ADES astCat
const _CATALOGS = Dict(
    'a' => "USNOA1", 'b' => "USNOSA1", 'c' => "USNOA2", 'd' => "USNOSA2", 'e' => "UCAC1",
    'f' => "Tyc1", 'g' => "Tyc2", 'h' => "GSC1.0", 'i' => "GSC1.1", 'j' => "GSC1.2",
    'k' => "GSC2.2", 'l' => "ACT", 'm' => "GSCACT", 'n' => "SDSS8", 'o' => "USNOB1",
    'p' => "PPM", 'q' => "UCAC4", 'r' => "UCAC2", 's' => "USNOB2", 't' => "PPMXL",
    'u' => "UCAC3", 'v' => "NOMAD", 'w' => "CMC14", 'x' => "Hip2", 'y' => "Hip1",
    'z' => "GSC", 'A' => "AC", 'B' => "SAO1984", 'C' => "SAO", 'D' => "AGK3", 'E' => "FK4",
    'F' => "ACRS", 'G' => "LickGas", 'H' => "Ida93", 'I' => "Perth70", 'J' => "COSMOS",
    'K' => "Yale", 'L' => "2MASS", 'M' => "GSC2.3", 'N' => "SDSS7", 'O' => "SSTRC1",
    'P' => "MPOSC3", 'Q' => "CMC15", 'R' => "SSTRC4", 'S' => "URAT1", 'T' => "URAT2",
    'U' => "Gaia1", 'V' => "Gaia2", 'W' => "Gaia3", 'X' => "Gaia3E", 'Y' => "UCAC5",
    'Z' => "ATLAS2", '0' => "IHW", '1' => "PS1_DR1", '2' => "PS1_DR2", '3' => "Gaia_Int",
    '4' => "GZ", '5' => "UBSC", '6' => "Gaia_2016", '7' => "ZZCAT", '8' => "APASS",
    '9' => "UBSC", '!' => "AKARI", '@' => "AG", '#' => "WISE", '$' => "LSST2502",
    '^' => "IRASPSC", '&' => "SDSS9", '*' => "SDSS16",
)
const _CATALOG_CODES = Dict(v => k for (k, v) in _CATALOGS if k != '5')   # UBSC => '9'

# ADES band => single-character 80-column band
const _BAND_TO_80 = Dict("Vj" => 'V', "VR" => 'V', "Rc" => 'R', "Rj" => 'R', "Ic" => 'I',
                         "Bj" => 'B', "Uj" => 'U', "Gb" => 'G', "Gr" => 'G')

# Program codes (column 14) and their 2-character ADES form
const _PROGRAM_CODES = raw"""0123456789!"#$%&'()*+,-./[\]^_`{|}~:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"""

"""
    PROGRAM_CODE_SITES

Observatory codes whose column 14 holds a program code rather than a note, from the
MPC observatory table as distributed with IAU-ADES/ADES-Master (April 2026). Pass a
different set to [`read_mpc80`](@ref) via `program_code_sites` if needed.
"""
const PROGRAM_CODE_SITES = Set(split("""
    010 012 033 071 084 089 094 095 098 119 121 181 186 204 209 245 246 247 249 250 251
    252 253 254 255 256 257 259 260 261 262 263 264 265 266 267 268 269 271 272 273 274
    275 287 288 289 290 291 308 309 323 327 336 338 339 413 561 566 568 644 645 658 673
    675 688 689 691 695 696 699 703 705 807 809 851 932 950 A84 B35 B63 C40 C49 C50 C51
    C53 C57 C58 C65 D20 D90 E03 E10 E26 E41 E42 E54 E62 E84 F51 F52 F65 G34 G37 G40 G73
    G83 G84 G96 H06 H45 I03 I05 I11 I18 I22 I33 I41 I52 I89 J04 J13 J26 J69 J75 J95 K91
    K92 K93 K99 L09 L28 L34 L80 L81 M18 M22 M49 N50 N53 O58 P21 Q12 Q14 Q54 Q55 Q58 Q59
    Q62 Q63 Q64 R16 R17 R44 R50 R51 R52 R53 R54 R55 R59 R60 R61 R62 R68 R70 R71 R72 R73
    R74 R75 R76 R77 R85 R92 R93 R97 R99 S04 S16 S42 S43 S47 S61 S89 T03 T04 T05 T08 T09
    T10 T11 T12 T13 T14 T15 T16 T17 U62 U65 U69 U92 U94 U95 V00 V06 V07 V26 V37 V38 V39
    V45 V46 V47 V48 V55 V57 W11 W26 W27 W36 W37 W38 W57 W68 W74 W76 W79 W84 W85 W86 W87
    W88 W89 W97 W98 X05 X06 X07 X11 X22 X23 X24 X25 X26 X27 Z17 Z18 Z19 Z20 Z21 Z23 Z24
    Z28 Z31 Z33 Z58 Z84
    """))

function _pack_prog(c::AbstractChar)
    i = findfirst(==(c), _PROGRAM_CODES)
    i === nothing && throw(ArgumentError("invalid program code '$c'"))
    return string(i - 1 > 61 ? '1' : '0', _b62((i - 1) % 62))
end
function _unpack_prog(s::AbstractString)
    length(s) == 2 || throw(ArgumentError("invalid ADES program code \"$s\""))
    i = 62 * _unb62(s[1]) + _unb62(s[2])
    return i < length(_PROGRAM_CODES) ? _PROGRAM_CODES[i+1] : ' '
end

# Publication references in columns 73-77
function _unpack_ref(p::AbstractString)
    c = p[1]
    isdigit(c) && return "MPC $(parse(Int, p))"
    c == '@' && return "MPC $(100000 + parse(Int, p[2:end]))"
    c == '#' && return "MPC $(110000 + _unb62(p[2:end]))"
    'a' <= c <= 'z' && return "MPS $(10000 * (c - 'a') + parse(Int, p[2:end]))"
    c == '~' && return "MPS $(260000 + _unb62(p[2:end]))"
    return String(p)
end
function _pack_ref(ref::AbstractString)
    m = match(r"^(MPC|MPS)\s+(\d+)$", ref)
    if m === nothing
        return length(ref) <= 5 ? rpad(ref, 5) : "     "
    end
    n = parse(Int, m[2])
    if m[1] == "MPC"
        n < 100000 && return lpad(n, 5, '0')
        n < 110000 && return "@" * lpad(n - 100000, 4, '0')
        return "#" * _b62(n - 110000, 4)
    end
    n < 260000 && return string('a' + div(n, 10000), lpad(n % 10000, 4, '0'))
    return "~" * _b62(n - 260000, 4)
end

# --- times and angles -----------------------------------------------------------

const _DATE80 = r"^(\d{4}) (\d{2}) (\d{2})\.(\d+) *$"

# "YYYY MM DD.dddddd" => (obsTime, precTime). obsTime is rounded to milliseconds, or to
# whole seconds with `intsec` (radar).
function _date80_to_iso(s::AbstractString; intsec::Bool=false)
    m = match(_DATE80, s)
    m === nothing && throw(ArgumentError("invalid 80-column date \"$s\""))
    frac = m[4]
    nd = length(frac)
    nd <= 6 || throw(ArgumentError("time precision too high for ADES in \"$s\""))
    unit = intsec ? 86400 : 86400000          # seconds or milliseconds per day
    num = parse(Int, frac) * unit
    den = 10^nd
    t = div(2num + den, 2den)                 # round half up
    dt = DateTime(parse(Int, m[1]), parse(Int, m[2]), parse(Int, m[3])) +
         (intsec ? Second(t) : Millisecond(t))
    iso = Dates.format(dt, intsec ? dateformat"yyyy-mm-ddTHH:MM:SS" : dateformat"yyyy-mm-ddTHH:MM:SS.sss") * "Z"
    return iso, string(10^(6 - nd))
end

# obsTime string => "YYYY MM DD.dddddd" (17 characters) with the precision of precTime.
function _iso_to_date80(iso::AbstractString, prectime::Real)
    y, mo, d, h, mi, sec, _ = _timeparts(iso)
    m = match(r"\.(\d+)", iso)
    fsec = m === nothing ? 0 // 1 : parse(Int, m[1]) // 10^length(m[1])
    nd = clamp(6 - floor(Int, log10(prectime)), 1, 6)
    day = ((h * 3600 + mi * 60 + sec) + fsec) / 86400       # exact rational
    q = round(Int, day * 10^nd, RoundNearestTiesUp)
    date = Date(y, mo, d)
    if q >= 10^nd                                          # rounded up to the next day
        q -= 10^nd
        date += Day(1)
    end
    return string(Dates.format(date, dateformat"yyyy mm dd"), ".", rpad(lpad(q, nd, '0'), 6))
end

# Sexagesimal "HH MM SS.ss" etc. => (hours, minutes, seconds, precision)
function _parse_sexagesimal(s::AbstractString)
    t = strip(s)
    m = match(r"^(\d{1,2})\s+(\d{1,2})\s+(\d{1,2})\.(\d*)$", t)
    m !== nothing && return parse(Int, m[1]), parse(Int, m[2]),
                            parse(Float64, m[3] * "." * m[4]), parse(Float64, "1e-$(length(m[4]))")
    m = match(r"^(\d{1,2})\s+(\d{1,2})\s+(\d{1,2})$", t)
    m !== nothing && return parse(Int, m[1]), parse(Int, m[2]), parse(Float64, m[3]), 1.0
    m = match(r"^(\d{1,2})\s+(\d{1,2}\.(\d{1,2}))$", t)
    m !== nothing && return parse(Int, m[1]), parse(Float64, m[2]), 0.0, length(m[3]) == 2 ? 0.6 : 6.0
    m = match(r"^(\d{1,2})\s+(\d{1,2})$", t)
    m !== nothing && return parse(Int, m[1]), parse(Float64, m[2]), 0.0, 60.0
    throw(ArgumentError("invalid sexagesimal value \"$s\""))
end

_prec_string(p::Real) = p >= 1 ? string(round(Int, p)) : _tostring(p)

# Number of decimals of a decimal-degree value matching a sexagesimal precision.
_deg_digits(prec, unit) = max(1, -floor(Int, log10(prec * unit)))

function _ra80_to_deg(s::AbstractString)
    h, m, sec, prec = _parse_sexagesimal(s)
    v = (h * 3600 + m * 60 + sec) * (360 / 86400)
    return @sprintf("%.*f", _deg_digits(prec, 360 / 86400), v), _prec_string(prec)
end

function _dec80_to_deg(s::AbstractString)
    sign = s[1]
    sign in ('+', '-', ' ') || throw(ArgumentError("invalid declination sign in \"$s\""))
    d, m, sec, prec = _parse_sexagesimal(s[2:end])
    v = (d + m / 60 + sec / 3600) * (sign == '-' ? -1 : 1)
    str = @sprintf("%.*f", _deg_digits(prec, 1 / 3600), v)
    sign == '-' && !startswith(str, "-") && (str = "-" * str)   # -00 00 01 rounds to -0.0
    return str, _prec_string(prec)
end

# Total seconds (of time or arc) => sexagesimal string padded to 12 characters.
function _to_sexagesimal(total::Float64, prefix::String, prec::Real, ra::Bool)
    if prec in (60, 6, 0.6)
        places = prec == 60 ? 0 : prec == 6 ? 1 : 2
        tm = round(total / 60; digits=places)
        ra ? (tm >= 1440 && (tm -= 1440)) : (tm = min(tm, 5400.0))
        h = floor(Int, tm / 60)
        mins = tm - 60h
        w = places == 0 ? 2 : places + 3
        s = @sprintf("%s%02d %0*.*f", prefix, h, w, places, mins)
    else
        places = max(0, round(Int, -log10(prec)))
        tt = round(total; digits=places)
        ra ? (tt >= 86400 && (tt -= 86400)) : (tt = min(tt, 324000.0))
        h = floor(Int, tt / 3600)
        rest = tt - 3600h
        mi = floor(Int, rest / 60)
        sec = rest - 60mi
        w = places == 0 ? 2 : places + 3
        s = @sprintf("%s%02d %02d %0*.*f", prefix, h, mi, w, places, sec)
    end
    return rpad(s, 12)
end

_ra_to_80(ra::AbstractString, prec::Real) = _to_sexagesimal(parse(Float64, ra) * 240, "", prec, true)
function _dec_to_80(dec::AbstractString, prec::Real)
    v = parse(Float64, dec)
    return _to_sexagesimal(abs(v) * 3600, (v < 0 || startswith(dec, "-")) ? "-" : "+", prec, false)
end

# Default precision when precRA/precDec are absent: from the number of decimals given.
function _default_prec(value::AbstractString, finest::Real, steps)
    m = match(r"\.(\d+)", value)
    nd = m === nothing ? 0 : length(m[1])
    for (digits, prec) in steps
        nd >= digits && return max(prec, finest)
    end
    return last(steps)[2]
end
_default_precra(ra) = _default_prec(ra, 0.001, ((6, 0.001), (5, 0.01), (4, 0.1), (0, 1.0)))
_default_precdec(dec) = _default_prec(dec, 0.01, ((6, 0.01), (5, 0.1), (0, 1.0)))

# Implied-decimal fields of the radar format; the zero padding of the fraction is dropped
# (ADES limits e.g. rmsDelay to 6 characters)
_trimzeros(s::AbstractString) = occursin('.', s) ? rstrip(rstrip(s, '0'), '.') : s
_implied(s::AbstractString, nint::Int) =
    isempty(strip(s)) ? "" : _trimzeros(strip(s[1:nint] * "." * s[nint+1:end]))
function _signed(s::AbstractString)   # "+   12.5" => "+12.5"
    v = strip(s[2:end])
    return s[1] == ' ' ? v : s[1] * v
end

# --- reading --------------------------------------------------------------------

const _HEADER80 = r"^(COD|CON|OBS|MEA|TEL|NET|BND|COM|NUM|ACK|AC2)(?: (.*))?$"
const _EXTRA_HEADERS = ("NET", "BND", "NUM", "ACK", "AC2")
const _TEL80 = r"^\s*(\d+(?:\.\d+)?)-m\s+(?:f/(\d+(?:\.\d+)?)\s+)?(.*?)\s*\+\s*(.+?)\s*$"

"""
    read_mpc80(source; program_code_sites=PROGRAM_CODE_SITES, submission=false) -> ADESData

Read observations in the MPC 80-column format (optical, roving `V/v`, satellite `S/s`
and radar `R/r` records) and convert them to ADES. `source` is a file path or an `IO`;
use [`parse_mpc80`](@ref) for a string.

Conversion follows the IAU-ADES reference converter:

- RA/Dec become decimal degrees with as many digits as the sexagesimal values carry;
  `precRA`, `precDec` and `precTime` record the original precision, so writing back with
  [`write_mpc80`](@ref) reproduces the line.
- `obsTime` is given to the millisecond (whole seconds for radar).
- Column 14 becomes `prog` for stations in `program_code_sites`, else `notes`.
- Codes `E` and `O` become `optical` records with mode `OCC` and `OFF`; `X`/`x` set
  `deprecated`; `A` (B1950 positions) sets `subFrm`.
- Radar records with both delay and Doppler are split into two ADES records.
- Header lines start a new `obsBlock`: `COD`, `CON`, `OBS`, `MEA`, `TEL` and `COM`
  map onto `obsContext`; other header lines (`NET`, `ACK`, ...) are kept as comment
  lines and written back as headers.

`submission=true` omits elements that the ADES submission schema does not allow
(`subFmt`, `precTime`, `precRA`, `precDec`, `subFrm`, `deprecated`, `prog`, `ref`).
"""
read_mpc80(path::AbstractString; kw...) = open(io -> read_mpc80(io; kw...), path)
read_mpc80(io::IO; kw...) = _read_mpc80(eachline(io); kw...)

"""
    parse_mpc80(str; kw...) -> ADESData

Parse MPC 80-column observations held in a string; see [`read_mpc80`](@ref).
"""
parse_mpc80(str::AbstractString; kw...) = _read_mpc80(eachline(IOBuffer(str)); kw...)

mutable struct _Header80
    lines::Vector{Tuple{String,String}}
end

function _context_from80(h::_Header80)
    ctx = ObsContext()
    get1(k) = (i = findfirst(p -> p[1] == k, h.lines); i === nothing ? nothing : h.lines[i][2])
    names(k) = [String(strip(n)) for n in split(something(get1(k), ""), ',') if !isempty(strip(n))]
    if (cod = get1("COD")) !== nothing
        push!(ctx, ContextSection("observatory", ["mpcCode" => strip(cod)]))
    end
    if (con = get1("CON")) !== nothing
        parts = split(con, ','; limit=2)
        e = ["name" => strip(parts[1])]
        length(parts) == 2 && push!(e, "institution" => strip(parts[2]))
        push!(ctx, ContextSection("submitter", e))
    end
    for (k, sec) in (("OBS", "observers"), ("MEA", "measurers"))
        n = names(k)
        isempty(n) || push!(ctx, ContextSection(sec, ["name" => x for x in n]))
    end
    if (tel = get1("TEL")) !== nothing
        e = ["name" => strip(tel)]
        m = match(_TEL80, tel)
        if m !== nothing
            push!(e, "design" => m[3], "aperture" => m[1], "detector" => m[4])
            m[2] === nothing || push!(e, "fRatio" => m[2])
        end
        push!(ctx, ContextSection("telescope", e))
    end
    comments = [k == "COM" ? v : "$k $v" for (k, v) in h.lines if k == "COM" || k in _EXTRA_HEADERS]
    isempty(comments) || push!(ctx, ContextSection("comment", ["line" => c for c in comments]))
    return ctx
end

function _read_mpc80(lines; program_code_sites=PROGRAM_CODE_SITES, submission::Bool=false)
    blocks = ObsBlock[]
    header = nothing      # header lines being collected
    block = nothing
    pending = nothing     # (code, fields, line) of a first line awaiting its second line
    for (lineno, raw) in enumerate(lines)
        line = rstrip(raw)
        isempty(line) && continue
        try
            hm = match(_HEADER80, line)
            if hm !== nothing
                pending === nothing || throw(ArgumentError("expected the second line of a two-line record"))
                if header === nothing
                    header = _Header80(Tuple{String,String}[])
                    block = nothing
                end
                push!(header.lines, (String(hm[1]), hm[2] === nothing ? "" : String(hm[2])))
                continue
            end
            length(line) <= 80 || throw(ArgumentError("line longer than 80 columns"))
            line = rpad(line, 80)
            if block === nothing || header !== nothing
                block = ObsBlock(header === nothing ? nothing : _context_from80(header), Observation[])
                push!(blocks, block)
                header = nothing
            end
            code = line[15]
            if pending !== nothing
                pcode, f, _ = pending
                code == lowercase(pcode) ||
                    throw(ArgumentError("'$pcode' line must be followed by a '$(lowercase(pcode))' line"))
                first80 = pending[3]
                line[1:14] == first80[1:14] && line[16:32] == first80[16:32] ||
                    throw(ArgumentError("second line does not match the first in columns 1-14 and 16-32"))
                append!(block.observations, _second_line80!(f, pcode, line, submission))
                pending = nothing
            elseif code in ('r', 's', 'v')
                throw(ArgumentError("'$code' line without a preceding '$(uppercase(code))' line"))
            else
                f = _first_line80(line, program_code_sites, submission)
                if code in ('R', 'S', 'V')
                    pending = (code, f, line)
                else
                    push!(block.observations, Observation(:optical, f))
                end
            end
        catch e
            e isa ArgumentError || rethrow()
            throw(ArgumentError("MPC 80-column line $lineno: $(e.msg)\n  $raw"))
        end
    end
    pending === nothing || throw(ArgumentError("MPC 80-column input ends inside a two-line record"))
    if header !== nothing     # header without data
        push!(blocks, ObsBlock(_context_from80(header), Observation[]))
    end
    return ADESData("2022", blocks)
end

function _ids80!(f::Dict{Symbol,String}, line::AbstractString)
    perm, prov, trk = unpack_designation(line[1:12])
    perm === nothing || (f[:permID] = perm)
    prov === nothing || (f[:provID] = prov)
    trk === nothing || (f[:trkSub] = trk)
end

function _first_line80(line::AbstractString, sites, submission::Bool)
    f = Dict{Symbol,String}()
    _ids80!(f, line)
    code = line[15]
    line[20] == ' ' || throw(ArgumentError("column 20 must be blank"))
    stn = String(strip(line[78:80]))
    f[:stn] = stn
    if code == 'R'
        f[:obsTime], _ = _date80_to_iso(line[16:32]; intsec=true)
        f[:delay] = _implied(line[33:47], 5)
        d = line[48:62]
        f[:doppler] = isempty(strip(d)) ? "" : _trimzeros(_signed(d[1:11] * "." * d[12:15]))
        f[:frq] = _implied(line[63:68], 5)
        f[:trx] = String(strip(line[69:71]))
        isempty(strip(line[73:77])) || submission || (f[:ref] = _unpack_ref(line[73:77]))
        return f
    end
    code in keys(_MODE_OF_CODE) || code in ('A', 'X', 'x', 'S', 'V') ||
        throw(ArgumentError("invalid code '$code' in column 15"))
    f[:obsTime], f[:precTime] = _date80_to_iso(line[16:32])
    f[:ra], f[:precRA] = _ra80_to_deg(line[33:44])
    f[:dec], f[:precDec] = _dec80_to_deg(line[45:56])
    disc = line[13]
    disc == ' ' || (f[:disc] = string(disc))
    note = line[14]
    if note != ' '
        if stn in sites
            f[:prog] = _pack_prog(note)
        else
            f[:notes] = string(note)
        end
    end
    if code in ('X', 'x')
        f[:deprecated] = "X"
        f[:mode] = "CCD"
    elseif code == 'A'
        f[:subFrm] = "B1950.0"
        f[:mode] = _MODE_OF_CODE['P']
    elseif code in ('S', 'V')
        f[:mode] = "CCD"
    else
        f[:mode] = _MODE_OF_CODE[code]
    end
    mag = strip(line[66:70])
    if !isempty(mag)
        f[:mag] = mag
        f[:band] = line[71] == ' ' ? "UNK" : string(line[71])
    end
    f[:astCat] = get(_CATALOGS, line[72], "UNK")
    isempty(strip(line[73:77])) || (f[:ref] = _unpack_ref(line[73:77]))
    submission || (f[:subFmt] = "M92")
    if submission
        for k in (:precTime, :precRA, :precDec, :subFrm, :deprecated, :prog, :ref)
            delete!(f, k)
        end
    end
    return f
end

# Combine a two-line record; returns the resulting observations.
function _second_line80!(f::Dict{Symbol,String}, code::Char, line::AbstractString, submission::Bool)
    # the reference may be given on either line
    submission || haskey(f, :ref) || isempty(strip(line[73:77])) || (f[:ref] = _unpack_ref(line[73:77]))
    if code == 'S'
        t = line[33]
        t in ('1', '2') || throw(ArgumentError("column 33 of an 's' line must be 1 or 2"))
        f[:sys] = t == '1' ? "ICRF_KM" : "ICRF_AU"
        f[:ctr] = "399"
        f[:pos1], f[:pos2], f[:pos3] = _signed(line[35:45]), _signed(line[47:57]), _signed(line[59:69])
        return [Observation(:optical, f)]
    elseif code == 'V'
        line[33] == '1' || throw(ArgumentError("column 33 of a 'v' line must be 1"))
        f[:sys] = "WGS84"
        f[:ctr] = "399"
        f[:pos1], f[:pos2], f[:pos3] = strip(line[35:44]), strip(line[46:55]), strip(line[57:61])
        isempty(f[:pos3]) && throw(ArgumentError("roving observation without altitude"))
        return [Observation(:optical, f)]
    end
    # radar
    sc = line[33]
    sc in ('S', 'C') || throw(ArgumentError("column 33 of an 'r' line must be S or C"))
    f[:com] = sc == 'C' ? "1" : "0"
    f[:rcv] = String(strip(line[78:80]))
    delete!(f, :stn)
    rmsdelay = _implied(line[34:47], 10)
    rmsdoppler = _implied(line[48:62], 11)
    cont = strip(line[63:68])
    isempty(cont) || isempty(f[:frq]) || (f[:frq] *= cont)
    delay, doppler = pop!(f, :delay), pop!(f, :doppler)
    out = Observation[]
    if !isempty(delay)
        g = copy(f)
        g[:delay] = delay
        isempty(rmsdelay) || (g[:rmsDelay] = rmsdelay)
        push!(out, Observation(:radar, g))
    end
    if !isempty(doppler)
        g = copy(f)
        g[:doppler] = doppler
        isempty(rmsdoppler) || (g[:rmsDoppler] = rmsdoppler)
        push!(out, Observation(:radar, g))
    end
    isempty(out) && throw(ArgumentError("radar record without delay or Doppler"))
    isempty(f[:frq]) && for o in out
        o.frq = missing
    end
    return out
end

# --- writing --------------------------------------------------------------------

"""
    write_mpc80(dest, data::ADESData)

Write `data` in the MPC 80-column format to `dest` (a file path or an `IO`).
`optical` and `radar` records are supported; other record kinds raise an error.

Positions are written with the precision in `precRA`/`precDec`/`precTime` where
present (as after reading 80-column data); otherwise RA/Dec precision follows the number
of decimals of the ADES values and times are written to 1e-6 day. Elements without an
80-column equivalent (uncertainties, `remarks`, ...) are dropped, and only the first
character of `notes` is kept.
"""
function write_mpc80(io::IO, d::ADESData)
    for b in d.blocks
        b.context === nothing || _write_header80(io, b.context)
        for o in b.observations
            if o.kind === :optical
                _write_optical80(io, o)
            elseif o.kind === :radar
                _write_radar80(io, o)
            else
                throw(ArgumentError("cannot write $(o.kind) records in the MPC 80-column format"))
            end
        end
    end
    return nothing
end
write_mpc80(path::AbstractString, d::ADESData) = open(io -> write_mpc80(io, d), path, "w")

"""
    mpc80_string(data::ADESData) -> String

`data` rendered in the MPC 80-column format.
"""
mpc80_string(d::ADESData) = sprint(write_mpc80, d)

function _write_header80(io::IO, ctx::ObsContext)
    sec(name) = haskey(ctx, name) ? ctx[name] : nothing
    if (s = sec("observatory")) !== nothing && haskey(s, "mpcCode")
        println(io, "COD ", s["mpcCode"])
    end
    if (s = sec("submitter")) !== nothing && haskey(s, "name")
        println(io, "CON ", join([s["name"]; getall(s, "institution")], ", "))
    end
    for (name, key) in (("observers", "OBS"), ("measurers", "MEA"))
        s = sec(name)
        s === nothing || println(io, key, " ", join(getall(s, "name"), ", "))
    end
    if (s = sec("telescope")) !== nothing
        if haskey(s, "name")
            println(io, "TEL ", s["name"])
        elseif haskey(s, "aperture")
            fr = haskey(s, "fRatio") ? " f/" * s["fRatio"] : ""
            println(io, "TEL ", s["aperture"], "-m", fr, " ", get(s, "design", ""), " + ", get(s, "detector", ""))
        end
    end
    if (s = sec("comment")) !== nothing
        for l in getall(s, "line")
            k = length(l) >= 3 ? l[1:3] : ""
            if k in _EXTRA_HEADERS && (length(l) == 3 || l[4] == ' ')
                println(io, l)
            else
                println(io, "COM ", l)
            end
        end
    end
end

_raw(o, k, default="") = (v = rawvalue(o, k); v === missing ? default : v)

function _packed_id80(o::Observation)
    haskey(o, :artSat) && return lpad(_raw(o, :artSat), 12)[1:12]
    return pack_designation(rawvalue(o, :permID), rawvalue(o, :provID), rawvalue(o, :trkSub))
end

function _mag80(mag::AbstractString)
    isempty(mag) && return "     "
    m = match(r"^(\d+)(?:\.(\d*))?$", mag)
    m === nothing && throw(ArgumentError("cannot write magnitude \"$mag\""))
    frac = something(m[2], "")
    if length(frac) > 2
        s = @sprintf("%.2f", parse(Float64, mag))
        m = match(r"^(\d+)\.(\d*)$", s)
        frac = m[2]
    end
    out = lpad(m[1], 2) * (isempty(frac) ? "" : "." * frac)
    length(out) <= 5 || throw(ArgumentError("cannot write magnitude \"$mag\""))
    return rpad(out, 5)
end

function _band80(band::AbstractString)
    (isempty(band) || band == "UNK") && return ' '
    haskey(_BAND_TO_80, band) && return _BAND_TO_80[band]
    return length(band) > 1 ? band[2] : band[1]
end

# Fixed-point field: sign, integer part right-aligned, decimal point at `point`.
function _fixed80(v::AbstractString, width::Int, point::Int; signed::Bool=true, pad::Char=' ')
    s = strip(v)
    sign = ""
    if signed
        sign = startswith(s, '-') ? "-" : "+"
        s = lstrip(s, ['+', '-'])
    end
    ip, fp = occursin('.', s) ? split(s, '.'; limit=2) : (s, "")
    nint = point - 1 - length(sign)
    nfrac = width - point
    if length(fp) > nfrac
        x = round(parse(Float64, s); digits=nfrac)
        ip, fp = split(@sprintf("%.*f", nfrac, x), '.')
    end
    length(ip) <= nint || throw(ArgumentError("value $v does not fit into the 80-column field"))
    return sign * lpad(ip, nint) * "." * rpad(fp, nfrac, pad)
end

function _write_optical80(io::IO, o::Observation)
    id = _packed_id80(o)
    disc = first(_raw(o, :disc, " "))
    note = haskey(o, :prog) ? _unpack_prog(_raw(o, :prog)) : first(_raw(o, :notes, " "))
    sys = rawvalue(o, :sys)
    code = if haskey(o, :deprecated)
        'X'
    elseif sys !== missing
        sys == "WGS84" ? 'V' : sys in ("ICRF_KM", "ICRF_AU") ? 'S' :
            throw(ArgumentError("sys = $sys cannot be written in the 80-column format"))
    elseif haskey(o, :subFrm)
        'A'
    else
        mode = _raw(o, :mode)
        haskey(_CODE_OF_MODE, mode) || throw(ArgumentError("mode \"$mode\" has no 80-column code"))
        _CODE_OF_MODE[mode]
    end
    prectime = haskey(o, :precTime) ? o.precTime : 1
    date = _iso_to_date80(_raw(o, :obsTime), prectime)
    ra, dec = _raw(o, :ra), _raw(o, :dec)
    precra = haskey(o, :precRA) ? o.precRA : _default_precra(ra)
    precdec = haskey(o, :precDec) ? o.precDec : _default_precdec(dec)
    mag = _raw(o, :mag)
    band = isempty(mag) ? ' ' : _band80(_raw(o, :band))
    cat = get(_CATALOG_CODES, _raw(o, :astCat), ' ')
    ref = haskey(o, :ref) ? _pack_ref(_raw(o, :ref)) : "     "
    stn = rpad(_raw(o, :stn), 3)
    head = string(id, disc, note)
    println(io, head, code, date, _ra_to_80(ra, precra), _dec_to_80(dec, precdec),
            " "^9, _mag80(mag), band, cat, ref, stn)
    code in ('V', 'S') || return
    p1, p2, p3 = _raw(o, :pos1), _raw(o, :pos2), _raw(o, :pos3)
    if code == 'V'
        println(io, head, 'v', date, "1 ", lpad(p1, 10), " ", lpad(p2, 10), " ", lpad(p3, 5),
                " "^10, " ", ref, stn)
    else
        point = sys == "ICRF_KM" ? 7 : 3
        println(io, head, 's', date, sys == "ICRF_KM" ? "1 " : "2 ",
                _fixed80(p1, 11, point), " ", _fixed80(p2, 11, point), " ", _fixed80(p3, 11, point),
                "   ", ref, stn)
    end
end

function _write_radar80(io::IO, o::Observation)
    id = _packed_id80(o)
    date = _iso_to_date80(_raw(o, :obsTime), 1)
    nodot(s) = replace(s, "." => "")
    blank(n) = " "^n
    delay = haskey(o, :delay) ? nodot(_fixed80(_raw(o, :delay), 16, 6; signed=false, pad='0')) : blank(15)
    doppler = haskey(o, :doppler) ? nodot(_fixed80(_raw(o, :doppler), 16, 12; pad='0')) : blank(15)
    rmsdelay = haskey(o, :rmsDelay) ? nodot(_fixed80(_raw(o, :rmsDelay), 15, 11; signed=false, pad='0')) : blank(14)
    rmsdoppler = haskey(o, :rmsDoppler) ? nodot(_fixed80(_raw(o, :rmsDoppler), 16, 12; signed=false, pad='0')) : blank(15)
    frq, cont = blank(6), blank(6)
    if haskey(o, :frq)
        ip, fp = occursin('.', _raw(o, :frq)) ? split(_raw(o, :frq), '.'; limit=2) : (_raw(o, :frq), "")
        length(ip) <= 5 || throw(ArgumentError("frequency $(_raw(o, :frq)) does not fit"))
        frq = lpad(ip, 5) * rpad(first(fp, 1), 1, '0')
        cont = rpad(length(fp) > 1 ? first(fp[2:end], 6) : "", 6)
    end
    trx = rpad(_raw(o, :trx), 3)
    rcv = rpad(_raw(o, :rcv), 3)
    ref = haskey(o, :ref) ? _pack_ref(_raw(o, :ref)) : "     "
    sc = _raw(o, :com, "0") == "1" ? 'C' : 'S'
    println(io, id, "  R", date, delay, doppler, frq, trx, " ", ref, rcv)
    println(io, id, "  r", date, sc, rmsdelay, rmsdoppler, cont, trx, " ", ref, rcv)
end
