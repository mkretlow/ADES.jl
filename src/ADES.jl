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
import EzXML
import Tables

export RECORD_KINDS, ELEMENT_ORDER, REQUIRED_ELEMENTS, element_type
export ContextSection, ObsContext, Observation, ObsBlock, ADESData
export getall, rawvalue, observations, designation, julian_date, obstable
export read_ades, parse_ades, write_ades
export read_xml, parse_xml, write_xml, xml_string
export read_psv, parse_psv, write_psv, psv_string
export validate

include("schema.jl")
include("types.jl")
include("xml.jl")
include("psv.jl")
include("table.jl")
include("validate.jl")

_isxml(str::AbstractString) = startswith(lstrip(str), "<")

"""
    read_ades(path) -> ADESData

Read an ADES file, either XML or PSV. The format is detected from the content: a file
whose first non-blank character is `<` is XML.
"""
function read_ades(path::AbstractString)
    str = read(path, String)
    return _isxml(str) ? parse_xml(str) : parse_psv(str)
end

"""
    parse_ades(str::AbstractString) -> ADESData

Parse ADES XML or PSV held in a string; the format is detected from the content.
"""
parse_ades(str::AbstractString) = _isxml(str) ? parse_xml(str) : parse_psv(str)

"""
    write_ades(path, data::ADESData; format=:auto, kw...)

Write `data` to `path`. With `format=:auto` the extension decides: `.xml` gives XML,
anything else PSV. Pass `format=:xml` or `format=:psv` to choose explicitly. Keyword
arguments go to [`write_psv`](@ref).
"""
function write_ades(path::AbstractString, d::ADESData; format::Symbol=:auto, kw...)
    if format === :auto
        format = lowercase(splitext(path)[2]) == ".xml" ? :xml : :psv
    end
    format === :xml && return write_xml(path, d)
    format === :psv && return write_psv(path, d; kw...)
    throw(ArgumentError("format must be :auto, :xml or :psv, got :$format"))
end

end # module ADES
