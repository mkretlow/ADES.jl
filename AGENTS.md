# ADES.jl

Julia package for IAU ADES astrometry (XML, PSV) and conversion from/to the MPC 80-column format.

## Commands

- Tests: `julia --project=. -e 'using Pkg; Pkg.test()'`
- Other Julia versions are installed under `/opt/julia-1.10LTS/usr/bin/julia` (source build), `/opt/julia-1.12`. Minimum
  supported is 1.10 (`Project.toml` compat and `.github/workflows/CI.yml`). Run the tests there
  too when touching syntax or Base APIs.

## Design rules

- `Observation` stores every value as the string from the file; typed values are parsed on
  property access. ADES encodes precision in the number of digits, so never reformat stored
  numbers. Round trips (XML <-> PSV <-> 80-column) must stay byte-exact for data lines.
- XML output must validate against the official schema: element order comes from
  `ELEMENT_ORDER` (src/schema.jl), and `obsData` may hold only one record kind (`write_xml`
  splits mixed blocks).
- 80-column conversion follows the IAU-ADES Python reference converters
  (`mpc80coltoxml.py`, `xmltompc80col.py`, `packUtil.py`, `sexVals.py`). Intentional
  deviations are documented in `pack_designation` and `read_mpc80`.
- Internal helpers keep a leading underscore (`_fixed80`); the API is the exported names.
  Decided against Julia 1.11 `public` + dropping underscores (also: 1.10 lacks `public`).
- Tests access Tables.jl as `ADES.Tables`: it is a package dependency, and a test target may
  only list `[extras]`.

## Reference material

Official spec, XSDs, sample files and Python tools: https://github.com/IAU-ADES/ADES-Master
(`xsd/general.xsd`, `xsd/submit.xsd`, `tests/input/`). Not vendored; clone it into a scratch
directory and validate output with
`xmllint --noout --schema <ADES-Master>/xsd/general.xsd file.xml`.
The "XSD validation" test does this for the fixtures when `ADES_MASTER=<ADES-Master>` is
set (CI pins a commit in `.github/workflows/CI.yml`).
The sample files there include deliberately invalid ones (version 2017, `fail_headers.psv`,
`trksub_9chars.xml`), so schema failures on those are expected.
