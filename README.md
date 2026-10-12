# ADES.jl

[![CI](https://github.com/mkretlow/ADES.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/mkretlow/ADES.jl/actions/workflows/CI.yml)

Read, write and inspect astrometric observations in the IAU **Astrometry Data Exchange
Standard (ADES)**, the format the Minor Planet Center (MPC) uses for submitting and
distributing observations of minor bodies.

Both ADES serializations are supported, plus conversion from and to the old format:

- **XML**: the canonical form, defined by the ADES XSD schema
- **PSV**: pipe-separated values, the human-readable tabular form
- **MPC 80-column** ("MPC1992", obs80): optical, roving, satellite and radar records

Supported record types: `optical`, `offset`, `occultation`, `radar`, and the
distribution records `opticalResidual` and `radarResidual`.

## Installation

```julia
using Pkg
Pkg.add(url="https://github.com/mkretlow/ADES.jl")   # not yet registered
```

## Quick start

```julia
using ADES

data = read_ades("observations.psv")      # or .xml / 80-column; format detected from content

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
write_ades("observations.xml", data)      # extension picks XML, PSV or 80-column (.obs/.mpc)
write_psv("observations.psv", data; align=true)
```

### MPC 80-column format

```julia
data = read_mpc80("observations.obs")     # also detected by read_ades
write_ades("observations.xml", data)      # 80-column -> ADES XML
write_mpc80("back.obs", data)             # ADES -> 80-column
mpc80_string(data)

unpack_designation("00433J98X00A")        # ("433", "1998 XA", nothing)
pack_designation(nothing, "C/1995 O1", nothing)   # "    CJ95O010"
```

The conversion follows the official IAU-ADES converters:

- Sexagesimal RA/Dec become decimal degrees with matching digits. `precRA`, `precDec`
  and `precTime` keep the original precision, so 80-column → ADES → 80-column reproduces
  the data lines exactly, also via XML or PSV.
- Header lines map onto `obsContext`: `COD` → observatory, `CON` → submitter, `OBS`/`MEA`
  → observers/measurers, `TEL` → telescope (aperture, f-ratio, design and detector are
  parsed where possible), `COM` → comment. `NET`, `ACK`, `AC2`, `BND` and `NUM` are kept
  as comment lines and written back as headers.
- Column 14 becomes `prog` for stations that use program codes (`PROGRAM_CODE_SITES`),
  otherwise `notes`. Codes `X`/`x` set `deprecated`, `A` sets `subFrm = B1950.0`.
- Radar records with both delay and Doppler become two ADES records, as ADES requires.
- `read_mpc80(...; submission=true)` leaves out elements the ADES submission schema does
  not allow (`subFmt`, `prec*`, `subFrm`, `deprecated`, `prog`, `ref`).

Writing 80-column data from ADES drops what that format cannot hold (uncertainties,
remarks, photometry details, ...). Without `prec*` elements, RA/Dec are written with the
precision implied by their number of decimals and times to 1e-6 day.


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
| `read_mpc80`, `parse_mpc80`, `write_mpc80`, `mpc80_string` | MPC 80-column I/O |
| `write_ades` | write; format chosen from the extension or `format=:xml/:psv/:mpc80` |
| `pack_designation`, `unpack_designation` | MPC packed designations (columns 1-12) |
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
- An XML `obsData` element may hold only one record type, so a block that mixes types is
  written as several `obsBlock`s sharing the same context.
- 80-column output supports `optical` and `radar` records; `offset`, `occultation` and
  residual records have no 80-column form.

## References

- ADES description and schema: <https://github.com/IAU-ADES/ADES-Master>
- MPC documentation on ADES: <https://www.minorplanetcenter.net/iau/info/ADES.html>

## License

MIT
