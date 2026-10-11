"""
    ContextSection(name, value="", entries=Pair{String,String}[])

One section of an `obsContext` header, such as `observatory`, `submitter`, `observers` or
`telescope`. `entries` holds the `key => value` lines in file order (e.g. one
`"name" => ...` per observer). Sections without children, like `fundingSource`, store
their text in `value`.

`sec["key"]` returns the first value for `key`; [`getall`](@ref) returns all of them.
"""
struct ContextSection
    name::String
    value::String
    entries::Vector{Pair{String,String}}
end
ContextSection(name::AbstractString, value::AbstractString="") =
    ContextSection(String(name), String(value), Pair{String,String}[])
ContextSection(name::AbstractString, entries::AbstractVector{<:Pair}) =
    ContextSection(String(name), "", [String(k) => String(v) for (k, v) in entries])

function Base.getindex(sec::ContextSection, key::AbstractString)
    for (k, v) in sec.entries
        k == key && return v
    end
    throw(KeyError(key))
end
function Base.get(sec::ContextSection, key::AbstractString, default)
    for (k, v) in sec.entries
        k == key && return v
    end
    return default
end
Base.haskey(sec::ContextSection, key::AbstractString) = any(p -> p.first == key, sec.entries)

"""
    getall(sec::ContextSection, key) -> Vector{String}

All values stored under `key`, e.g. `getall(ctx["observers"], "name")`.
"""
getall(sec::ContextSection, key::AbstractString) = [v for (k, v) in sec.entries if k == key]

"""
    ObsContext(sections=ContextSection[])

The `obsContext` header of an observation block. `ctx["telescope"]` returns the
section with that name.
"""
struct ObsContext
    sections::Vector{ContextSection}
end
ObsContext() = ObsContext(ContextSection[])

function Base.getindex(ctx::ObsContext, name::AbstractString)
    for s in ctx.sections
        s.name == name && return s
    end
    throw(KeyError(name))
end
Base.haskey(ctx::ObsContext, name::AbstractString) = any(s -> s.name == name, ctx.sections)
Base.push!(ctx::ObsContext, sec::ContextSection) = (push!(ctx.sections, sec); ctx)

"""
    Observation(kind::Symbol, fields::Dict{Symbol,String})
    Observation(kind::Symbol; element=value, ...)

A single ADES record: `kind` is one of [`RECORD_KINDS`](@ref).

Values are stored as the strings found in the file, so the number of digits (which ADES
uses to express precision) survives a read/write round trip. Property access parses
them: `obs.ra` gives a `Float64`, `obs.obsTime` a `DateTime`, `obs.stn` a `String`, and
an element that is not present gives `missing`. Assigning (`obs.mag = 18.3`) or passing
keywords to the constructor stores the value's string form; pass a string to control
the number of digits written.

Use [`rawvalue`](@ref) for the stored string and `haskey(obs, :ra)` to test presence.
"""
struct Observation
    kind::Symbol
    fields::Dict{Symbol,String}
    function Observation(kind::Symbol, fields::Dict{Symbol,String})
        kind in RECORD_KINDS || throw(ArgumentError("unknown ADES record kind :$kind"))
        new(kind, fields)
    end
end
function Observation(kind::Symbol; kwargs...)
    fields = Dict{Symbol,String}()
    for (k, v) in kwargs
        v === missing || v === nothing || (fields[k] = _tostring(v))
    end
    return Observation(kind, fields)
end

_fields(o::Observation) = getfield(o, :fields)

function Base.getproperty(o::Observation, name::Symbol)
    name === :kind && return getfield(o, :kind)
    name === :fields && return getfield(o, :fields)
    s = get(_fields(o), name, nothing)
    s === nothing && return missing
    return _parsevalue(name, s)
end
function Base.setproperty!(o::Observation, name::Symbol, v)
    name in (:kind, :fields) && throw(ArgumentError("cannot set Observation field $name"))
    if v === missing || v === nothing
        delete!(_fields(o), name)
    else
        _fields(o)[name] = _tostring(v)
    end
    return v
end
Base.propertynames(o::Observation) = (:kind, sort!(collect(keys(_fields(o))))...)

Base.haskey(o::Observation, name::Symbol) = haskey(_fields(o), name)
Base.getindex(o::Observation, name::Symbol) = getproperty(o, name)
Base.setindex!(o::Observation, v, name::Symbol) = setproperty!(o, name, v)
Base.:(==)(a::Observation, b::Observation) = a.kind == b.kind && _fields(a) == _fields(b)
Base.hash(o::Observation, h::UInt) = hash(_fields(o), hash(o.kind, h))
Base.copy(o::Observation) = Observation(o.kind, copy(_fields(o)))

"""
    rawvalue(obs, name) -> Union{String,Missing}

The string stored for element `name`, exactly as read from the file.
"""
rawvalue(o::Observation, name::Symbol) = get(_fields(o), name, missing)

"""
    ObsBlock(context, observations)

An `obsBlock`: an [`ObsContext`](@ref) header and its observations. Records that ADES
places outside any `obsBlock` (as in distribution files) go into a block whose
`context` is `nothing`.
"""
struct ObsBlock
    context::Union{ObsContext,Nothing}
    observations::Vector{Observation}
end

"""
    ADESData(version, blocks)
    ADESData(context, observations; version="2022")

The contents of an ADES file. Iterating over it yields every observation in file order;
[`observations`](@ref) collects them into a vector and [`obstable`](@ref) turns them into
a column table.
"""
struct ADESData
    version::String
    blocks::Vector{ObsBlock}
end
ADESData(ctx::Union{ObsContext,Nothing}, obs::AbstractVector{Observation}; version::AbstractString="2022") =
    ADESData(String(version), [ObsBlock(ctx, collect(obs))])

"""
    observations(data::ADESData) -> Vector{Observation}

All observations of all blocks, in file order.
"""
observations(d::ADESData) = reduce(vcat, (b.observations for b in d.blocks); init=Observation[])

Base.length(d::ADESData) = sum((length(b.observations) for b in d.blocks); init=0)
Base.eltype(::Type{ADESData}) = Observation
function Base.iterate(d::ADESData, state=(1, 1))
    bi, oi = state
    while bi <= length(d.blocks)
        obs = d.blocks[bi].observations
        oi <= length(obs) && return obs[oi], (bi, oi + 1)
        bi, oi = bi + 1, 1
    end
    return nothing
end

# ---------------------------------------------------------------------------------------
# Value conversion

const _TIME_RE = r"^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?Z?$"

function _timeparts(s::AbstractString)
    m = match(_TIME_RE, s)
    m === nothing && throw(ArgumentError("invalid ADES obsTime \"$s\""))
    y, mo, d, h, mi, sec = (parse(Int, m.captures[i]) for i in 1:6)
    frac = m.captures[7] === nothing ? 0.0 : parse(Float64, "0." * m.captures[7])
    return y, mo, d, h, mi, sec, frac
end

# A leap second (ss = 60) rolls over into the next minute, since DateTime cannot hold it.
function _parsetime(s::AbstractString)
    y, mo, d, h, mi, sec, frac = _timeparts(s)
    return DateTime(y, mo, d, h, mi) + Second(sec) + Millisecond(round(Int, frac * 1000))
end

function _parsevalue(name::Symbol, s::String)
    T = element_type(name)
    T === String && return s
    T === DateTime && return _parsetime(s)
    v = tryparse(T, s)
    v === nothing && throw(ArgumentError("cannot parse ADES element $name = \"$s\" as $T"))
    return v
end

_tostring(x::AbstractString) = String(x)
_tostring(x::Integer) = string(x)
_tostring(x::DateTime) = Dates.format(x, dateformat"yyyy-mm-ddTHH:MM:SS.sss") * "Z"
function _tostring(x::AbstractFloat)
    isfinite(x) || throw(ArgumentError("ADES values must be finite, got $x"))
    s = string(Float64(x))
    occursin('e', s) || return s
    # ADES decimal types do not allow exponents: shift the shortest digits by hand
    m, e = split(s, 'e')
    neg = startswith(m, "-")
    ip, fp = split(lstrip(m, '-'), '.')
    digs = rstrip(ip * fp, '0')
    point = length(ip) + parse(Int, e)
    out = point <= 0 ? "0." * "0"^(-point) * digs :
          point >= length(digs) ? digs * "0"^(point - length(digs)) :
          digs[1:point] * "." * digs[point+1:end]
    return neg ? "-" * out : out
end
_tostring(x) = string(x)

# ---------------------------------------------------------------------------------------
# Convenience accessors

"""
    designation(obs) -> Union{String,Missing}

The best available object identifier: `permID`, else `provID`, else `artSat`, else
`trkSub`.
"""
function designation(o::Observation)
    for k in (:permID, :provID, :artSat, :trkSub)
        haskey(o, k) && return _fields(o)[k]
    end
    return missing
end

"""
    julian_date(obs) -> Float64

The observation time `obsTime` as a UTC Julian date, computed from the stored string,
so sub-millisecond digits are kept up to the resolution of `Float64` (about 40 µs at
current epochs).
"""
function julian_date(o::Observation)
    s = rawvalue(o, :obsTime)
    s === missing && throw(ArgumentError("observation has no obsTime"))
    y, mo, d, h, mi, sec, frac = _timeparts(s)
    return datetime2julian(DateTime(y, mo, d)) + (h * 3600 + mi * 60 + sec + frac) / 86400
end

# ---------------------------------------------------------------------------------------
# Display

function Base.show(io::IO, o::Observation)
    print(io, "Observation(:", o.kind)
    for k in (:permID, :provID, :artSat, :trkSub, :stn, :obsTime)
        haskey(o, k) && print(io, ", ", k, "=", repr(_fields(o)[k]))
    end
    print(io, ")")
end

function Base.show(io::IO, ::MIME"text/plain", o::Observation)
    println(io, "ADES ", o.kind, " observation:")
    order = get(ELEMENT_ORDER, o.kind, Symbol[])
    ks = [k for k in order if haskey(o, k)]
    append!(ks, sort!([k for k in keys(_fields(o)) if !(k in order)]))
    w = maximum(length ∘ string, ks; init=0)
    for (i, k) in enumerate(ks)
        print(io, "  ", rpad(string(k), w), " = ", _fields(o)[k])
        i < length(ks) && println(io)
    end
end

function Base.show(io::IO, ctx::ObsContext)
    print(io, "ObsContext(", join((s.name for s in ctx.sections), ", "), ")")
end

function Base.show(io::IO, ::MIME"text/plain", ctx::ObsContext)
    print(io, "ObsContext:")
    for s in ctx.sections
        print(io, "\n  ", s.name, isempty(s.value) ? "" : " " * s.value)
        for (k, v) in s.entries
            print(io, "\n    ", k, " ", v)
        end
    end
end

function Base.show(io::IO, b::ObsBlock)
    code = b.context !== nothing && haskey(b.context, "observatory") ?
           get(b.context["observatory"], "mpcCode", "?") : "-"
    print(io, "ObsBlock(observatory=", code, ", ", length(b.observations), " observations)")
end

function Base.show(io::IO, d::ADESData)
    print(io, "ADESData(version=", d.version, ", ", length(d.blocks), " blocks, ",
          length(d), " observations)")
end

function Base.show(io::IO, ::MIME"text/plain", d::ADESData)
    show(io, d)
    for b in d.blocks
        print(io, "\n  ")
        show(io, b)
    end
end
