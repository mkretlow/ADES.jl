# ADES PSV (pipe-separated values) reading and writing
#
# PSV layout:
#   # version=2022          format version
#   # observatory           obsContext section ('#' lines)
#   ! mpcCode 568           section entries ('!' lines)
#   permID |stn |obsTime    keyword line: column names (all start with a letter)
#   433    |568 |2020-...   data lines
# A '#' line after data starts a new obsBlock. The record kind of a table is
# inferred from its columns.

"""
    read_psv(source) -> ADESData

Read an ADES PSV file. `source` is a file path or an `IO`. Use [`parse_psv`](@ref)
for a string.
"""
read_psv(path::AbstractString) = open(read_psv, path)
read_psv(io::IO) = _read_psv(eachline(io))

"""
    parse_psv(str::AbstractString) -> ADESData

Parse ADES PSV held in a string.
"""
parse_psv(str::AbstractString) = _read_psv(eachline(IOBuffer(str)))

_iskeyword(c::AbstractChar) = isletter(c) || c == '_'

function _split_header(rest::AbstractString)
    parts = split(strip(rest), r"\s+"; limit=2)
    return String(parts[1]), length(parts) > 1 ? String(parts[2]) : ""
end

function _read_psv(lines)
    version = ""
    blocks = ObsBlock[]
    ctx = nothing          # context being read from '#'/'!' lines
    block = nothing        # block receiving data lines
    cols = Symbol[]
    kind = :optical
    after_data = false
    for (lineno, line) in enumerate(lines)
        l = strip(line)
        isempty(l) && continue
        c = first(l)
        if c == '#'
            rest = strip(l[nextind(l, 1):end])
            m = match(r"^version\s*=\s*(\S+)", rest)
            if m !== nothing
                version = String(m.captures[1])
                continue
            end
            if ctx === nothing || after_data
                ctx = ObsContext()
                block = nothing
                cols = Symbol[]
                after_data = false
            end
            name, value = _split_header(rest)
            push!(ctx, ContextSection(name, value))
        elseif c == '!'
            (ctx === nothing || isempty(ctx.sections)) &&
                throw(ArgumentError("PSV line $lineno: '!' line outside of a '#' section"))
            key, value = _split_header(l[nextind(l, 1):end])
            push!(ctx.sections[end].entries, key => value)
        else
            fields = strip.(split(l, '|'))
            iskw = length(fields) > 1 && isempty(fields[end]) ? fields[1:end-1] : fields
            if all(f -> !isempty(f) && _iskeyword(first(f)), iskw)
                cols = Symbol.(iskw)
                kind = _infer_kind(cols)
                if block === nothing || (ctx !== nothing && block.context !== ctx)
                    block = ObsBlock(ctx, Observation[])
                    push!(blocks, block)
                end
            else
                isempty(cols) &&
                    throw(ArgumentError("PSV line $lineno: data line before any keyword line"))
                # tolerate a trailing '|'
                length(fields) == length(cols) + 1 && isempty(fields[end]) && pop!(fields)
                length(fields) == length(cols) || throw(ArgumentError(
                    "PSV line $lineno: $(length(fields)) fields, but the keyword line has $(length(cols))"))
                d = Dict{Symbol,String}()
                for (k, v) in zip(cols, fields)
                    isempty(v) || (d[k] = String(v))
                end
                push!(block.observations, Observation(kind, d))
                after_data = true
            end
        end
    end
    return ADESData(version, blocks)
end

"""
    write_psv(dest, data::ADESData; align=true)

Write `data` as ADES PSV to `dest` (a file path or an `IO`). With `align=true` the
columns are padded to a common width, which is easier to read. Each block's columns
are the elements present in at least one of its records, in schema order; a new keyword
line starts whenever the record kind changes. `localUse` content is not representable
in PSV and is dropped.
"""
function write_psv(io::IO, d::ADESData; align::Bool=true)
    println(io, "# version=", isempty(d.version) ? "2022" : d.version)
    for b in d.blocks
        if b.context !== nothing
            for s in b.context.sections
                println(io, "# ", s.name, isempty(s.value) ? "" : " " * s.value)
                for (k, v) in s.entries
                    println(io, "! ", k, " ", v)
                end
            end
        end
        for run in _kind_runs(b.observations)
            _write_psv_table(io, run, align)
        end
    end
    return nothing
end
write_psv(path::AbstractString, d::ADESData; kw...) = open(io -> write_psv(io, d; kw...), path, "w")

"""
    psv_string(data::ADESData; align=true) -> String

`data` rendered as ADES PSV.
"""
psv_string(d::ADESData; kw...) = sprint(io -> write_psv(io, d; kw...))

# Split observations into consecutive runs of the same kind.
function _kind_runs(obs::Vector{Observation})
    runs = Vector{Vector{Observation}}()
    for o in obs
        if isempty(runs) || runs[end][1].kind != o.kind
            push!(runs, [o])
        else
            push!(runs[end], o)
        end
    end
    return runs
end

function _write_psv_table(io::IO, obs::Vector{Observation}, align::Bool)
    order = ELEMENT_ORDER[obs[1].kind]
    present = Set{Symbol}()
    for o in obs
        union!(present, keys(_fields(o)))
    end
    delete!(present, :localUse)
    cols = [k for k in order if k in present]
    append!(cols, sort!([k for k in present if !(k in order)]))
    rows = [[get(_fields(o), k, "") for k in cols] for o in obs]
    widths = align ? [maximum(r -> length(r[i]), rows; init=length(string(c)))
                      for (i, c) in enumerate(cols)] : zeros(Int, length(cols))
    _psv_line(io, string.(cols), widths)
    for r in rows
        _psv_line(io, r, widths)
    end
end

function _psv_line(io::IO, vals, widths)
    n = length(vals)
    for i in 1:n
        print(io, i < n ? rpad(vals[i], widths[i]) : vals[i])
        i < n && print(io, '|')
    end
    println(io)
end
