# =============================================================
# Sensor Data Analysis & Prediction (RStudio-ready)
# Author: Anatolie Jentimir
# Date: 2025-10-28 (updated: multi-predictor lm)
# =============================================================

suppressPackageStartupMessages({
  library(tidyverse)
  library(lubridate)
  library(janitor)
  library(caret)
})

DATA_PATH <- file.path("data", "Sensor_Data.csv")
PLOT_DIR  <- "figs"
if (!dir.exists(dirname(DATA_PATH))) dir.create(dirname(DATA_PATH), recursive = TRUE)
if (!dir.exists(PLOT_DIR)) dir.create(PLOT_DIR, recursive = TRUE)

stopifnot(file.exists(DATA_PATH))

df <- readr::read_csv(DATA_PATH, show_col_types = FALSE) %>%
  janitor::clean_names()

cat("Loaded rows:", nrow(df), " cols:", ncol(df), "\n")
print(glimpse(df))

# ---- Numeric summaries ----
num_df <- df %>% select(where(is.numeric))
summary_tbl <- num_df %>%
  summarise(across(everything(), list(
    sum    = ~sum(.x, na.rm = TRUE),
    mean   = ~mean(.x, na.rm = TRUE),
    median = ~median(.x, na.rm = TRUE)
  )))
cat("\n=== Numeric Summary (sum/mean/median) ===\n"); print(summary_tbl)

# ---- Median timestamp if present ----
maybe_time <- df %>% select(matches("time|date|timestamp|datetime"))
if (ncol(maybe_time) >= 1) {
  tcol <- names(maybe_time)[1]
  tvec <- suppressWarnings(parse_date_time(df[[tcol]],
                                           orders = c("Ymd HMS","Ymd HM","Ymd","mdY HMS","mdY HM","mdY","dmy HMS","dmy HM","dmy")))
  if (any(!is.na(tvec))) {
    med_time <- median(as.numeric(tvec), na.rm = TRUE) %>% as.POSIXct(origin = "1970-01-01", tz = "UTC")
    cat("Median", tcol, ":", format(med_time, "%Y-%m-%d %H:%M:%S %Z"), "\n")
  }
}

# ---- Example visualization (auto columns) ----
plot_x <- NULL; plot_y <- NULL
if (all(c("temperature","humidity") %in% names(df))) {
  plot_x <- "temperature"; plot_y <- "humidity"
} else if (ncol(num_df) >= 2) {
  plot_x <- names(num_df)[1]; plot_y <- names(num_df)[2]
}

if (!is.null(plot_x) && !is.null(plot_y)) {
  p <- ggplot(df, aes(x = .data[[plot_x]], y = .data[[plot_y]])) +
    geom_point() + geom_smooth(method = "lm", se = TRUE) + theme_minimal() +
    labs(title = paste0(plot_x, " vs ", plot_y), x = plot_x, y = plot_y)
  print(p)
  ggsave(filename = file.path(PLOT_DIR, paste0(plot_x, "_vs_", plot_y, ".png")),
         plot = p, width = 7, height = 5, dpi = 150)
}

# =============================================================
# Linear model (lm): MULTIPLE PREDICTORS as requested
# Target: humidity
# Predictors: temperature + soil moisture (various possible column names)
# Fallback: auto formula if required columns not found
# =============================================================

col_exists <- function(options, data) {
  opts <- options[options %in% names(data)]
  if (length(opts) >= 1) opts[1] else NA_character_
}

humidity_col <- col_exists(c("humidity","rel_humidity","humidity_pct"), df)
temp_col     <- col_exists(c("temperature","temp","temperature_c"), df)
soil_col     <- col_exists(c("soil_moisture","soilmoisture","soil_moisture_pct","soil_moisture_percent"), df)

use_multi <- !is.na(humidity_col) && !is.na(temp_col) && !is.na(soil_col)

if (use_multi) {
  form <- as.formula(paste(humidity_col, "~", paste(c(temp_col, soil_col), collapse = " + ")))
  cat("\nModel formula (multi):", deparse(form), "\n")
} else {
  # Fallback to auto: last numeric as target, others as predictors
  num_cols <- names(num_df)
  stopifnot(length(num_cols) >= 2)
  target <- if (!is.na(humidity_col)) humidity_col else tail(num_cols, 1)
  predictors <- setdiff(num_cols, target)
  form <- as.formula(paste(target, "~", paste(predictors, collapse = " + ")))
  cat("\nModel formula (auto fallback):", deparse(form), "\n")
}

fit <- lm(form, data = df)
cat("\n=== lm() Summary ===\n"); print(summary(fit))

df$predicted <- predict(fit, newdata = df)
RMSE <- sqrt(mean((df[[all.vars(form)[1]]] - df$predicted)^2, na.rm = TRUE))
R2   <- cor(df[[all.vars(form)[1]]], df$predicted, use = "complete.obs")^2
cat(sprintf("\nRMSE: %.4f\nR^2:  %.4f\n", RMSE, R2))

# ---- Predicted vs Actual plot ----
pp <- ggplot(df, aes(x = .data[[all.vars(form)[1]]], y = predicted)) +
  geom_point() + geom_abline(intercept = 0, slope = 1, linetype = "dashed") +
  theme_minimal() +
  labs(title = paste("Predicted vs Actual:", all.vars(form)[1]),
       x = paste("Actual", all.vars(form)[1]),
       y = paste("Predicted", all.vars(form)[1]))
print(pp)

ggsave(filename = file.path(PLOT_DIR, paste0("pred_vs_actual_", all.vars(form)[1], ".png")),
       plot = pp, width = 7, height = 5, dpi = 150)

cat("\nDone. Figures saved in ./figs\n")
