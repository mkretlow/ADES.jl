"""
    ADES

Read, write and inspect astrometric observations in the IAU Astrometry Data Exchange
Standard (ADES), the format used by the Minor Planet Center. Both serializations are
supported: XML and PSV (pipe-separated values).

```julia
using ADES
data = read_ades("obs.psv")        # or .xml
for obs in data
    println(designation(obs), "  ", obs.obsTime, "  ", obs.ra, "  ", obs.dec)
end
write_ades("obs.xml", data)
```
"""
module ADES

using Dates
using Printf
import EzXML
import Tables

export RECORD_KINDS, ELEMENT_ORDER, REQUIRED_ELEMENTS, element_type
export ContextSection, ObsContext, Observation, ObsBlock, ADESData
export getall, rawvalue, observations, designation, julian_date, obstable
export read_ades, parse_ades, write_ades
export read_xml, parse_xml, write_xml, xml_string
export read_psv, parse_psv, write_psv, psv_string
export validate
export pack_designation, unpack_designation
export read_mpc80, parse_mpc80, write_mpc80, mpc80_string, PROGRAM_CODE_SITES

include("schema.jl")
include("designations.jl")
include("types.jl")
include("xml.jl")
include("psv.jl")
include("table.jl")
include("validate.jl")
include("mpc80.jl")

# Detect the format of observation data: :xml, :psv or :mpc80.
function _detect_format(str::AbstractString)
    s = lstrip(str)
    startswith(s, "<") && return :xml
    (startswith(s, "#") || startswith(s, "!") || occursin('|', s)) && return :psv
    return :mpc80
end

function _parse_any(str::AbstractString)
    fmt = _detect_format(str)
    fmt === :xml && return parse_xml(str)
    fmt === :psv && return parse_psv(str)
    return parse_mpc80(str)
end

"""
    read_ades(path) -> ADESData

Read an observation file in ADES XML, ADES PSV or the MPC 80-column format. The format
is detected from the content: XML starts with `<`, PSV contains `|` or starts with a
`#`/`!` header line, anything else is read as 80-column data.
"""
read_ades(path::AbstractString) = _parse_any(read(path, String))

"""
    parse_ades(str::AbstractString) -> ADESData

Parse ADES XML, ADES PSV or MPC 80-column data held in a string; the format is detected
from the content as in [`read_ades`](@ref).
"""
parse_ades(str::AbstractString) = _parse_any(str)

"""
    write_ades(path, data::ADESData; format=:auto, kw...)

Write `data` to `path`. With `format=:auto` the extension decides: `.xml` gives XML,
`.obs` or `.mpc` the MPC 80-column format, anything else PSV. Pass `format=:xml`,
`format=:psv` or `format=:mpc80` to choose explicitly. Keyword arguments go to
[`write_psv`](@ref).
"""
function write_ades(path::AbstractString, d::ADESData; format::Symbol=:auto, kw...)
    if format === :auto
        ext = lowercase(splitext(path)[2])
        format = ext == ".xml" ? :xml : ext in (".obs", ".mpc") ? :mpc80 : :psv
    end
    format === :xml && return write_xml(path, d)
    format === :psv && return write_psv(path, d; kw...)
    format === :mpc80 && return write_mpc80(path, d)
    throw(ArgumentError("format must be :auto, :xml, :psv or :mpc80, got :$format"))
end

end # module ADES
