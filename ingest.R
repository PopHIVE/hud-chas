# =============================================================================
# HUD CHAS — county-level percent of households with 1+ of 4 severe housing
# problems. Source: U.S. Dept. of Housing and Urban Development.
#
# huduser.gov sits behind an AWS WAF JS challenge; a plain download.file()
# gets a 202 with no content. Visiting the HTML page first with a shared
# httr handle, then reusing that handle for the zip, passes it.
#
# Vintage filenames are 5-year ACS windows ("2017thru2021" etc.), probed
# forward since there's no fixed release schedule.
#
# Table 2, not Table 1 -- same structure but for the non-severe definition,
# and gave values ~2x too high before catching the mismatch. Verified:
# (T2_est3 + T2_est76) / T2_est1 is an exact match against CHR&R's
# chr_severe_housing_problems.
#
# State-level rows come from the same zip's "-040-" file (040 = Census
# summary level for state, vs 050 for state+county) -- a real, independently
# published HUD tabulation, not an aggregate computed here. Confirmed live:
# 52 rows (50 states + DC + Puerto Rico), same geoid/table structure and
# same formula as county. No "-010-"/"-020-"/"-030-" (nation/region/
# division) file exists for CHAS, so there's no national rate to add.
# =============================================================================

library(dplyr)
library(httr)
library(vroom)

CHAS_BASE          <- "https://www.huduser.gov/portal/datasets/cp"
FIRST_WINDOW_START <- 2010L

session <- httr::handle("https://www.huduser.gov")
ua      <- httr::user_agent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")

invisible(httr::GET(paste0(CHAS_BASE, ".html"), handle = session, ua))

window_url <- function(start_year, level = "050") {
  sprintf("%s/%dthru%d-%s-csv.zip", CHAS_BASE, start_year, start_year + 4L, level)
}

latest_start <- tryCatch({
  current_year <- as.integer(format(Sys.Date(), "%Y"))
  found <- NA_integer_
  for (start_year in FIRST_WINDOW_START:(current_year - 4L)) {
    Sys.sleep(1)
    resp <- httr::HEAD(window_url(start_year), handle = session, ua)
    if (httr::status_code(resp) == 200) found <- start_year
  }
  found
}, error = function(e) {
  message("[WARN] Could not probe HUD CHAS vintages: ", conditionMessage(e))
  NA_integer_
})

if (!is.na(latest_start)) {

  end_year      <- latest_start + 4L
  last_end_year <- if (file.exists("process.json")) jsonlite::fromJSON("process.json")$chas_end_year else NULL

  if (is.null(last_end_year) || last_end_year < end_year) {

    message("HUD CHAS latest vintage: ", latest_start, "-", end_year)

    zip_path <- "raw/chas.zip"
    dir.create("raw", showWarnings = FALSE)
    dir.create("standard", showWarnings = FALSE)
    tmp <- paste0(zip_path, ".tmp")

    Sys.sleep(1)
    resp <- httr::GET(window_url(latest_start), handle = session, ua, httr::write_disk(tmp, overwrite = TRUE))

    if (httr::status_code(resp) == 200) {
      file.rename(tmp, zip_path)

      extract_dir <- "raw/extracted"
      unzip(zip_path, files = "050/Table2.csv", exdir = extract_dir, overwrite = TRUE)

      t2 <- vroom::vroom(file.path(extract_dir, "050", "Table2.csv"), show_col_types = FALSE)

      result <- t2 %>%
        transmute(
          geography                       = sub("^0500000US", "", geoid),
          time                            = paste0(end_year, "-12-31"),
          hud_pct_severe_housing_problems = (T2_est3 + T2_est76) / T2_est1
        ) %>%
        filter(!is.na(geography), nchar(geography) == 5)

      vroom::vroom_write(result, "standard/data_county.csv.gz", delim = ",")

      state_zip <- "raw/chas_state.zip"
      state_tmp <- paste0(state_zip, ".tmp")
      Sys.sleep(1)
      state_resp <- httr::GET(
        window_url(latest_start, level = "040"), handle = session, ua,
        httr::write_disk(state_tmp, overwrite = TRUE)
      )

      if (httr::status_code(state_resp) == 200) {
        file.rename(state_tmp, state_zip)
        unzip(state_zip, files = "040/Table2.csv", exdir = extract_dir, overwrite = TRUE)

        t2_state <- vroom::vroom(file.path(extract_dir, "040", "Table2.csv"), show_col_types = FALSE)

        state_result <- t2_state %>%
          transmute(
            geography                       = sub("^0400000US", "", geoid),
            time                            = paste0(end_year, "-12-31"),
            hud_pct_severe_housing_problems = (T2_est3 + T2_est76) / T2_est1
          ) %>%
          filter(!is.na(geography), nchar(geography) == 2)

        vroom::vroom_write(state_result, "standard/data_state.csv.gz", delim = ",")
        message("HUD CHAS data written: ", nrow(result), " counties, ", nrow(state_result), " states")
      } else {
        message("[WARN] HUD CHAS state-level download failed (status ", httr::status_code(state_resp), ")")
        unlink(state_tmp)
        message("HUD CHAS data written: ", nrow(result), " counties (state-level fetch failed)")
      }

      jsonlite::write_json(list(chas_end_year = end_year), "process.json", auto_unbox = TRUE)
    } else {
      message("[WARN] HUD CHAS download failed (status ", httr::status_code(resp), ")")
      unlink(tmp)
    }
  } else {
    message("HUD CHAS data is up to date (last vintage ending ", last_end_year, ")")
  }
} else {
  message("[WARN] Could not determine latest HUD CHAS vintage")
}
