# Column-table view of observations (Tables.jl compatible)

const _ALL_ELEMENTS = unique!(reduce(vcat, (ELEMENT_ORDER[k] for k in RECORD_KINDS)))

"""
    obstable(data; raw=false) -> NamedTuple of vectors

A column table of the observations in `data` (an [`ADESData`](@ref) or a vector of
[`Observation`](@ref)s), with a `kind` column followed by one column per element present
in any record, in schema order. Values are parsed as by property access, with `missing`
where a record lacks the element; with `raw=true` all columns hold the stored strings.

The result is a Tables.jl column table, so `DataFrame(obstable(data))` works. `ADESData`
itself also implements the Tables.jl interface.
"""
obstable(d::ADESData; kw...) = obstable(observations(d); kw...)
function obstable(obs::AbstractVector{Observation}; raw::Bool=false)
    present = Set{Symbol}()
    for o in obs
        union!(present, keys(_fields(o)))
    end
    delete!(present, :localUse)
    cols = [k for k in _ALL_ELEMENTS if k in present]
    append!(cols, sort!([k for k in present if !(k in _ALL_ELEMENTS)]))
    vecs = Any[Symbol[o.kind for o in obs]]
    for k in cols
        T = raw ? String : element_type(k)
        v = Vector{Union{Missing,T}}(missing, length(obs))
        for (i, o) in enumerate(obs)
            s = get(_fields(o), k, nothing)
            s === nothing || (v[i] = raw ? s : _parsevalue(k, s))
        end
        push!(vecs, v)
    end
    return NamedTuple{Tuple([:kind; cols])}(Tuple(vecs))
end

Tables.istable(::Type{ADESData}) = true
Tables.columnaccess(::Type{ADESData}) = true
Tables.columns(d::ADESData) = obstable(d)
