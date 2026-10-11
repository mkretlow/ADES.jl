# ADES.jl

Read, write and inspect astrometric observations in the IAU **Astrometry Data Exchange
Standard (ADES)**, the format the Minor Planet Center (MPC) uses for submitting and
distributing observations of minor bodies.

Both ADES serializations are supported:

- **XML**: the canonical form, defined by the ADES XSD schema
- **PSV**: pipe-separated values, the human-readable tabular form

Supported record types: `optical`, `offset`, `occultation`, `radar`, and the
distribution records `opticalResidual` and `radarResidual`.

## Installation

```julia
using Pkg
Pkg.develop(path="/path/to/ADES.jl")   # not yet registered
```

## Quick start

```julia
using ADES

data = read_ades("observations.psv")      # or .xml; format detected from content

# observatory context of the first block
ctx = data.blocks[1].context
ctx["observatory"]["mpcCode"]             # "J95"
getall(ctx["observers"], "name")          # ["A. Observer", "B. Helper"]

# iterate over observations
for obs in data
    println(designation(obs), "  ", obs.obsTime, "  ", obs.ra, "  ", obs.dec)
end

obs = first(data)
obs.ra              # 120.1234567 :: Float64
obs.obsTime         # DateTime
obs.mag             # missing if absent
rawvalue(obs, :dec) # "+20.123456" (exactly as in the file)
julian_date(obs)    # UTC Julian date with sub-millisecond digits kept

# convert between formats
write_ades("observations.xml", data)      # extension picks XML or PSV
write_psv("observations.psv", data; align=true)
```

### Values keep their precision

ADES expresses measurement precision through the number of digits written
(`ra = 120.12346` vs. `120.1234567`). `ADES.jl` therefore stores every value as
the string found in the file and parses it only when accessed. A read/write round trip
leaves the numbers unchanged.

### Tables and DataFrames

`ADESData` implements the Tables.jl interface. `obstable` returns a column table
(a `NamedTuple` of vectors) with typed columns and `missing` where an element is
absent:

```julia
using DataFrames
df = DataFrame(data)              # or DataFrame(obstable(data))
obstable(data; raw=true)          # all columns as stored strings
```

### Creating observations

```julia
using Dates
obs = Observation(:optical;
    provID = "2024 AB12", mode = "CCD", stn = "J95",
    obsTime = DateTime(2024, 1, 15, 21, 3, 12, 250),
    ra = "120.12346", dec = "+20.12346",   # strings control the digits written
    rmsRA = 0.12, rmsDec = 0.11, astCat = "Gaia3E",
    mag = 19.5, band = "G")
obs.remarks = "fast mover"

ctx = ObsContext([
    ContextSection("observatory", ["mpcCode" => "J95"]),
    ContextSection("submitter",   ["name" => "A. Observer"]),
    ContextSection("measurers",   ["name" => "A. Observer"]),
    ContextSection("telescope",   ["design" => "Reflector", "aperture" => "0.41",
                                   "detector" => "CCD"]),
])

data = ADESData(ctx, [obs])
validate(data)                     # String[] if no problems were found
write_ades("submission.xml", data)
```

### Validation

`validate(data; submission=true)` returns a list of problems: missing required elements
or identifiers, elements not allowed in a record type, an incomplete location group,
values that do not parse, out-of-range coordinates, over-long strings, and missing
`obsContext` entries needed for an MPC submission. It is a quick sanity check, not a
full XSD validation. For that, use the official tools in
[IAU-ADES/ADES-Master](https://github.com/IAU-ADES/ADES-Master).

## API overview

| Function | Purpose |
|---|---|
| `read_ades`, `parse_ades` | read a file or string, XML or PSV auto-detected |
| `read_xml`, `parse_xml`, `write_xml`, `xml_string` | XML I/O |
| `read_psv`, `parse_psv`, `write_psv`, `psv_string` | PSV I/O |
| `write_ades` | write; format chosen from the extension or `format=:xml/:psv` |
| `observations` | all observations as a `Vector{Observation}` |
| `obstable` | column table of observations (Tables.jl) |
| `designation` | `permID`, else `provID`, else `artSat`, else `trkSub` |
| `julian_date` | `obsTime` as a UTC Julian date |
| `rawvalue` | stored string of an element |
| `getall` | all values of a key in an `obsContext` section |
| `validate` | sanity checks |
| `element_type`, `ELEMENT_ORDER`, `REQUIRED_ELEMENTS`, `RECORD_KINDS` | schema info |

## Notes and limitations

- `obsTime` as a `DateTime` is rounded to milliseconds, and a leap second (`23:59:60`)
  rolls over into the next minute. Use `rawvalue` or `julian_date` for full precision.
- `localUse` content is kept verbatim for XML but cannot be represented in PSV.
- In PSV, the record type of a table is inferred from its columns (e.g. `raStar` means
  `occultation`, `trx`/`delay`/`doppler` means `radar`).
- Converting from and to the old MPC 80-column format is not implemented yet.

## References

- ADES description and schema: <https://github.com/IAU-ADES/ADES-Master>
- MPC documentation on ADES: <https://www.minorplanetcenter.net/iau/info/ADES.html>

## License

MIT
