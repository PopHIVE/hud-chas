# hud-chas

Ingests HUD Comprehensive Housing Affordability Strategy (CHAS) county-level
severe housing problems data for [PopHIVE](https://pophive.org).

## Output

`standard/data_county.csv.gz` — `geography` (5-digit county FIPS), `time`
(`YYYY-12-31`, the end year of the latest available 5-year vintage), and
`hud_pct_severe_housing_problems` (proportion, 0-1).

## Usage

```r
source("ingest.R")
```

No API key required, but note: huduser.gov sits behind an AWS WAF challenge
that blocks plain HTTP requests. `ingest.R` handles this with a shared
`httr` session (visit the HTML page first, then reuse that session's
cookies for the zip download) — a bare `download.file()` will not work
here.

## Consumed by

[PopHIVE/Ingest](https://github.com/PopHIVE/Ingest)'s
`data/hud_chas/ingest.R` pulls this repo's `standard/data_county.csv.gz`
and `measure_info.json` directly from GitHub, following the same pattern
as `PopHIVE/bureau-labor-statistics` and `PopHIVE/usda-food-access`.
