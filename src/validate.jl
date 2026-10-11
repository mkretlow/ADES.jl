# Lightweight consistency checks. This is not a full XSD validation; for that, use the
# official tools from IAU-ADES/ADES-Master.

const _CONTEXT_REQUIRED = [
    ("observatory", "mpcCode"), ("submitter", "name"), ("measurers", "name"),
    ("telescope", "design"), ("telescope", "aperture"), ("telescope", "detector"),
]

"""
    validate(data::ADESData; submission=true) -> Vector{String}

Check `data` against the main ADES rules and return a list of problems (empty if none
were found). It checks required elements and identifiers per record kind, the
completeness of the location group, that values parse with their expected type, value
ranges of `ra`, `dec`, `rmsCorr` and `stn`, and that no value contains `|`. With
`submission=true` it also checks that each block has the `obsContext` entries required
for submitting to the MPC.

This is not a full schema validation; use the official IAU-ADES tools for that.
"""
function validate(d::ADESData; submission::Bool=true)
    problems = String[]
    d.version in ("2017", "2022") || push!(problems, "unknown ADES version \"$(d.version)\"")
    n = 0
    for (bi, b) in enumerate(d.blocks)
        if submission
            if b.context === nothing
                push!(problems, "block $bi: no obsContext")
            else
                for (sec, key) in _CONTEXT_REQUIRED
                    if !haskey(b.context, sec) || !haskey(b.context[sec], key)
                        push!(problems, "block $bi: obsContext lacks $sec/$key")
                    end
                end
            end
        end
        for o in b.observations
            n += 1
            for p in _validate_record(o)
                push!(problems, "observation $n ($(o.kind)): $p")
            end
        end
    end
    return problems
end

const _MAX_LENGTH = Dict{Symbol,Int}(
    :permID => 25, :provID => 25, :artSat => 25, :trkSub => 8, :obsID => 25,
    :obsSubID => 35, :trkID => 12, :trkMPC => 12, :mode => 3, :prog => 2, :astCat => 8,
    :photCat => 8, :band => 3, :fltr => 3, :ref => 28, :subFmt => 4, :notes => 6,
    :remarks => 300, :orbProd => 100, :orbID => 25, :photProd => 100, :photMod => 8,
)

function _validate_record(o::Observation)
    p = String[]
    f = _fields(o)
    allowed = ELEMENT_ORDER[o.kind]
    for k in sort!(collect(keys(f)))
        k in allowed || push!(p, "element $k is not allowed in a $(o.kind) record")
        n = get(_MAX_LENGTH, k, typemax(Int))
        length(f[k]) > n && push!(p, "$k = \"$(f[k])\" is longer than $n characters")
    end
    for k in REQUIRED_ELEMENTS[o.kind]
        haskey(f, k) || push!(p, "missing required element $k")
    end
    o.kind in (:opticalResidual, :radarResidual) ||
        any(k -> haskey(f, k), (:permID, :provID, :artSat, :trkSub)) ||
        push!(p, "no identifier (permID, provID, artSat or trkSub)")
    if any(k -> haskey(f, k), _LOCATION)
        for k in (:sys, :ctr, :pos1, :pos2, :pos3)
            haskey(f, k) || push!(p, "location group incomplete: missing $k")
        end
    end
    if o.kind === :radar
        haskey(f, :delay) || haskey(f, :doppler) || push!(p, "radar record needs delay or doppler")
    end
    for (k, s) in f
        k === :localUse && continue
        occursin('|', s) && push!(p, "$k contains '|'")
        v = try
            _parsevalue(k, s)
        catch
            push!(p, "$k = \"$s\" is not a valid $(element_type(k))")
            continue
        end
        if k in (:ra, :raStar, :pa) && !(0 <= v < 360)
            push!(p, "$k = $s outside [0, 360)")
        elseif k in (:dec, :decStar) && !(-90 <= v <= 90)
            push!(p, "$k = $s outside [-90, 90]")
        elseif k in (:rmsCorr, :sigCorr) && !(-1 < v < 1)
            push!(p, "$k = $s outside (-1, 1)")
        elseif k in (:stn, :trx, :rcv) && !(3 <= length(s) <= 4)
            push!(p, "$k = \"$s\" must have 3 or 4 characters")
        end
    end
    return p
end
