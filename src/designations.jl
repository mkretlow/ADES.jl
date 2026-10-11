# Packing and unpacking of MPC designations (columns 1-12 of the 80-column format).
# See https://www.minorplanetcenter.net/iau/info/PackedDes.html

const _B62 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
const _ORDER_LETTERS = "ABCDEFGHJKLMNOPQRSTUVWXYZ"   # 25 letters, no I
const _PLANETS = Dict('J' => "Jupiter", 'S' => "Saturn", 'U' => "Uranus", 'N' => "Neptune")
const _PLANET_LETTERS = Dict(v => k for (k, v) in _PLANETS)

function _unb62(c::AbstractChar)
    i = findfirst(==(c), _B62)
    i === nothing && throw(ArgumentError("invalid base-62 digit '$c'"))
    return i - 1
end
_b62(n::Integer) = _B62[n+1]
_unb62(s::AbstractString) = foldl((n, c) -> 62n + _unb62(c), s; init=0)
function _b62(n::Integer, width::Integer)
    0 <= n < 62^width || throw(ArgumentError("$n does not fit in $width base-62 digits"))
    return String([_b62(div(n, 62^k) % 62) for k in width-1:-1:0])
end

# Two-digit cycle count: 0-99 as digits, then a letter and a digit up to 619.
function _pack_cycle(n::Integer)
    0 <= n <= 619 || throw(ArgumentError("order number $n out of range 0-619"))
    return string(_b62(div(n, 10)), n % 10)
end
_unpack_cycle(c1, c2) = 10 * _unb62(c1) + parse(Int, c2)

_nz(n) = n == 0 ? "" : string(n)

function _pack_century(y::AbstractString; minor_planet::Bool=false)
    c = parse(Int, y[1:2])
    minor_planet && !(18 <= c <= 20) && throw(ArgumentError("year $y out of range for a minor planet designation"))
    return string(_b62(c), y[3:4])
end

# --- minor planets --------------------------------------------------------------

const _MP_PACKED = Regex(string(
    raw"^(?: {5}|([0-9A-Za-z])(\d{4})|~([0-9A-Za-z]{4}))",
    raw"(?:([I-K])(\d{2})([A-HJ-Y])([a-zA-Z0-9])(\d)(?:([A-HJ-Z])|0)",
    raw"|(PL|T1|T2|T3)S(\d{4})",
    raw"|_([P-Z])([A-HJ-Y])([0-9A-Za-z]{4})",
    raw"|([-A-Za-z0-9]{0,7}) *)$"))

function _unpack_mp(m)
    permID = provID = trkSub = nothing
    if m[1] !== nothing
        n = 10000 * _unb62(m[1][1]) + parse(Int, m[2])
        n == 0 && throw(ArgumentError("minor planet number is zero"))
        permID = string(n)
    elseif m[3] !== nothing
        permID = string(620000 + _unb62(m[3]))
    end
    if m[4] !== nothing
        year = string(100 * _unb62(m[4][1]) + parse(Int, m[5]))
        n = _unpack_cycle(m[7][1], m[8])
        provID = m[9] === nothing ? "A/$year $(m[6])$(_nz(n))" : "$year $(m[6])$(m[9])$(_nz(n))"
    elseif m[10] !== nothing
        provID = "$(m[11]) $(m[10][1])-$(m[10][2])"
    elseif m[12] !== nothing
        seq = 15500 + _unb62(m[14])
        provID = "$(2000 + _unb62(m[12][1])) $(m[13])$(_ORDER_LETTERS[seq % 25 + 1])$(div(seq, 25))"
    elseif m[15] !== nothing && !isempty(m[15])
        trkSub = String(m[15])
    end
    return permID, provID, trkSub
end

function _pack_mp_number(s::AbstractString)
    n = parse(Int, s)
    n <= 0 && throw(ArgumentError("minor planet number must be positive: $s"))
    n < 100000 && return lpad(n, 5, '0')
    n < 620000 && return string(_b62(div(n, 10000)), lpad(n % 10000, 4, '0'))
    return "~" * _b62(n - 620000, 4)
end

const _MP_PROV = r"^(\d{4}) ([A-HJ-Y])([A-HJ-Z])(\d*)$"
const _MP_SURVEY = r"^(\d{4}) (P-L|T-1|T-2|T-3)$"
const _COMET_PROV = r"^([ACDPXI])/(\d{4}) ([A-HJ-Y])([A-HJ-Z]?)(\d*)(?:-([A-Z]))?$"
const _SAT_PROV = r"^S/(\d{4}) ([JSUN]) (\d+)$"

# Packed columns 6-12 of a minor planet provisional designation.
function _pack_mp_prov(provID::AbstractString)
    m = match(_MP_SURVEY, provID)
    m !== nothing && return string(m[2][1], m[2][3], "S", m[1])
    m = match(_MP_PROV, provID)
    if m !== nothing
        n = isempty(m[4]) ? 0 : parse(Int, m[4])
        if n > 619   # extended format for more than 15500 designations per half-month
            year = parse(Int, m[1])
            2025 <= year <= 2035 || throw(ArgumentError("cannot pack $provID: order number too large"))
            seq = 25n + findfirst(==(m[3][1]), _ORDER_LETTERS) - 1
            return string("_", _b62(year - 2000), m[2], _b62(seq - 15500, 4))
        end
        return string(_pack_century(m[1]; minor_planet=true), m[2], _pack_cycle(n), m[3])
    end
    m = match(_COMET_PROV, provID)   # A/ objects: asteroids on cometary orbits
    if m !== nothing && m[1] == "A" && isempty(m[4]) && m[6] === nothing && !isempty(m[5])
        return string(_pack_century(m[2]; minor_planet=true), m[3], _pack_cycle(parse(Int, m[5])), "0")
    end
    return nothing
end

# --- comets ---------------------------------------------------------------------

const _COMET_PACKED = Regex(string(
    raw"^(?: {4}|(\d{4}))([APCDXI])",
    raw"(?:([0-9A-Za-z])(\d{2})([A-HJ-Y])([a-zA-Z0-9])(\d)(?:0|([A-Z])|([a-z]))",
    raw"|     ([a-z ])([a-z])",
    raw"| *)$"))

function _unpack_comet(m)
    permID = provID = nothing
    kind = m[2]
    if m[1] !== nothing
        n = parse(Int, m[1])
        n == 0 && throw(ArgumentError("comet number is zero"))
        kind in ("P", "D", "I") || throw(ArgumentError("numbered comet must be of type P, D or I, not $kind"))
        permID = "$n$kind"
        m[9] !== nothing && (permID *= "-" * uppercase(m[9]))
        m[11] !== nothing && (permID *= "-" * uppercase(strip(m[10] * m[11])))
    end
    if m[3] !== nothing
        year = 100 * _unb62(m[3][1]) + parse(Int, m[4])
        n = _unpack_cycle(m[6][1], m[7])
        second = m[8] === nothing ? "" : m[8]
        frag = m[9] === nothing ? "" : "-" * uppercase(m[9])
        provID = "$kind/$year $(m[5])$second$(_nz(n))$frag"
    end
    return permID, provID, nothing
end

const _COMET_PERM = r"^(\d+)([PDI])(?:-([A-Z]{1,2}))?$"

# --- natural satellites ---------------------------------------------------------

const _SAT_PACKED = r"^(?: {4}|([JSUN])(\d{3}))S(?:([0-9A-Za-z])(\d{2})([JSUN])([a-zA-Z0-9])(\d)0| *)$"
const _SAT_PERM = r"^(Jupiter|Saturn|Uranus|Neptune) (\d+)$"

function _unpack_sat(m)
    permID = provID = nothing
    if m[1] !== nothing
        n = parse(Int, m[2])
        n == 0 && throw(ArgumentError("satellite number is zero"))
        permID = "$(_PLANETS[m[1][1]]) $n"
    end
    if m[3] !== nothing
        year = 100 * _unb62(m[3][1]) + parse(Int, m[4])
        n = _unpack_cycle(m[6][1], m[7])
        n == 0 && throw(ArgumentError("satellite number is zero"))
        provID = "S/$year $(m[5]) $n"
    end
    return permID, provID, nothing
end

# --- public API -----------------------------------------------------------------

"""
    unpack_designation(packed::AbstractString) -> (permID, provID, trkSub)

Unpack the 12-character object designation of an MPC 80-column record (columns 1-12)
into ADES identifiers. Absent identifiers are `nothing`.

```julia
unpack_designation("00433J98X00A")  # ("433", "1998 XA", nothing)
unpack_designation("    CJ95O010")  # (nothing, "C/1995 O1", nothing)
unpack_designation("     ABC1234")  # (nothing, nothing, "ABC1234")
```
"""
function unpack_designation(packed::AbstractString)
    s = rpad(packed, 12)
    length(s) == 12 || throw(ArgumentError("packed designation longer than 12 characters: \"$packed\""))
    for (re, f) in ((_MP_PACKED, _unpack_mp), (_COMET_PACKED, _unpack_comet), (_SAT_PACKED, _unpack_sat))
        m = match(re, s)
        m === nothing && continue
        ids = f(m)
        all(isnothing, ids) && break
        return ids
    end
    throw(ArgumentError("not a valid packed MPC designation: \"$packed\""))
end

_none(x) = x === nothing || x === missing || isempty(x)

"""
    pack_designation(permID, provID, trkSub) -> String

Pack ADES identifiers into the 12-character designation field of the MPC 80-column
format. Pass `nothing` (or `missing`) for absent identifiers. The trkSub is only used
when there is neither a permID nor a provID, and must fit into 7 characters.

```julia
pack_designation("433", "1998 XA", nothing)   # "00433J98X00A"
pack_designation(nothing, nothing, "ABC1234") # "     ABC1234"
```
"""
function pack_designation(permID, provID, trkSub)
    if _none(permID) && _none(provID)
        _none(trkSub) && throw(ArgumentError("no identifier to pack"))
        occursin(r"^[-A-Za-z0-9]{1,7}$", trkSub) ||
            throw(ArgumentError("trkSub \"$trkSub\" cannot be written in the 80-column format (max. 7 characters)"))
        return "     " * rpad(trkSub, 7)
    end
    perm = _none(permID) ? nothing : String(permID)
    prov = _none(provID) ? nothing : String(provID)
    bad() = throw(ArgumentError("cannot pack permID \"$perm\" with provID \"$prov\""))

    pclass = perm === nothing ? nothing :
             occursin(r"^\d+$", perm) ? :mp :
             occursin(_COMET_PERM, perm) ? :comet :
             occursin(_SAT_PERM, perm) ? :sat :
             throw(ArgumentError("cannot pack permID \"$perm\""))
    vclass = prov === nothing ? nothing :
             occursin(_SAT_PROV, prov) ? :sat :
             (occursin(_MP_PROV, prov) || occursin(_MP_SURVEY, prov)) ? :mp :
             occursin(_COMET_PROV, prov) ? :comet :
             throw(ArgumentError("cannot pack provID \"$prov\""))
    class = something(pclass, vclass)
    if vclass !== nothing && vclass != class
        # A/ designations go into the minor planet layout when the object is numbered
        (class === :mp && startswith(prov, "A/")) || bad()
    end

    if class === :sat
        head = "    "
        if perm !== nothing
            pm = match(_SAT_PERM, perm)
            n = parse(Int, pm[2])
            1 <= n <= 999 || throw(ArgumentError("satellite number out of range: $perm"))
            head = string(_PLANET_LETTERS[pm[1]], lpad(n, 3, '0'))
        end
        tail = "       "
        if prov !== nothing
            vm = match(_SAT_PROV, prov)
            n = parse(Int, vm[3])
            n >= 1 || throw(ArgumentError("satellite number must be positive: $prov"))
            tail = string(_pack_century(vm[1]), vm[2], _pack_cycle(n), "0")
        end
        return head * "S" * tail
    end

    if class === :comet
        pm = perm === nothing ? nothing : match(_COMET_PERM, perm)
        vm = prov === nothing ? nothing : match(_COMET_PROV, prov)
        kind = pm !== nothing ? pm[2] : vm[1]
        pm !== nothing && vm !== nothing && vm[1] != kind && bad()
        head = "    "
        frag = pm === nothing ? nothing : pm[3]
        if pm !== nothing
            n = parse(Int, pm[1])
            1 <= n <= 9999 || throw(ArgumentError("comet number out of range: $perm"))
            head = lpad(n, 4, '0')
        end
        if vm === nothing
            tail = frag === nothing ? "       " : "     " * lpad(lowercase(frag), 2)
        else
            vfrag = vm[6]
            pm !== nothing && frag != vfrag && bad()
            second, digits = vm[4], vm[5]
            !isempty(second) && vfrag !== nothing && throw(ArgumentError("cannot pack provID \"$prov\""))
            isempty(second) && isempty(digits) && throw(ArgumentError("cannot pack provID \"$prov\""))
            n = isempty(digits) ? 0 : parse(Int, digits)
            last = !isempty(second) ? second : vfrag !== nothing ? lowercase(vfrag) : "0"
            tail = string(_pack_century(vm[2]), vm[3], _pack_cycle(n), last)
        end
        return head * kind * tail
    end

    # minor planets
    head = perm === nothing ? "     " : _pack_mp_number(perm)
    tail = "       "
    if prov !== nothing
        t = _pack_mp_prov(prov)
        t === nothing && throw(ArgumentError("cannot pack provID \"$prov\""))
        tail = t
    end
    return head * tail
end
