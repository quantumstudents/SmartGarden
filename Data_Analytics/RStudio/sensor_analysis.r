# =============================================================
# Sensor Data Analysis & Prediction (RStudio-ready)
# Author: Anatolie Jentimir
# Date: 2025-10-28
# Project layout (recommended):
#   data/Sensor_Data.csv  - raw data
#   R/sensor_analysis.R   - this script (optionally)
#   figs/                 - saved plots
# =============================================================

# ---- Libraries ----
suppressPackageStartupMessages({
  library(tidyverse)
  library(lubridate)
  library(janitor)
  library(caret)
})

# ---- Config ----
DATA_PATH <- file.path("data", "Sensor_Data.csv")
PLOT_DIR  <- "figs"

# Create dirs if needed
if (!dir.exists(dirname(DATA_PATH))) dir.create(dirname(DATA_PATH), recursive = TRUE)
if (!dir.exists(PLOT_DIR)) dir.create(PLOT_DIR, recursive = TRUE)

# ---- Load ----
stopifnot(file.exists(DATA_PATH))

df <- readr::read_csv(DATA_PATH, show_col_types = FALSE) %>%
  janitor::clean_names()

cat("Loaded rows:", nrow(df), " cols:", ncol(df), "\n")

# ---- Inspect ----
print(glimpse(df))
print(head(df))
print(summary(df))

# ---- Numeric summaries (sum/mean/median per numeric column) ----
num_df <- df %>% select(where(is.numeric))

summary_tbl <- num_df %>%
  summarise(across(everything(), list(
    sum    = ~sum(.x, na.rm = TRUE),
    mean   = ~mean(.x, na.rm = TRUE),
    median = ~median(.x, na.rm = TRUE)
  )))

cat("\n=== Numeric Summary (sum/mean/median) ===\n")
print(summary_tbl)

# ---- Median date/time if present ----
maybe_time <- df %>% select(matches("time|date|timestamp|datetime"))
if (ncol(maybe_time) >= 1) {
  tcol <- names(maybe_time)[1]
  tvec <- suppressWarnings(parse_date_time(df[[tcol]],
                                           orders = c("Ymd HMS", "Ymd HM", "Ymd",
                                                      "mdY HMS", "mdY HM", "mdY",
                                                      "dmy HMS", "dmy HM", "dmy")))
  if (any(!is.na(tvec))) {
    med_time <- median(as.numeric(tvec), na.rm = TRUE) %>% as.POSIXct(origin = "1970-01-01", tz = "UTC")
    cat("Median", tcol, ":", format(med_time, "%Y-%m-%d %H:%M:%S %Z"), "\n")
  }
}

# ---- Example visualization (edit column names as needed) ----
# If columns 'temperature' and 'humidity' exist, plot them; otherwise auto-pick two numeric columns.
plot_x <- NULL; plot_y <- NULL
if (all(c("temperature", "humidity") %in% names(df))) {
  plot_x <- "temperature"; plot_y <- "humidity"
} else if (ncol(num_df) >= 2) {
  plot_x <- names(num_df)[1]; plot_y <- names(num_df)[2]
}

if (!is.null(plot_x) && !is.null(plot_y)) {
  p <- ggplot(df, aes(x = .data[[plot_x]], y = .data[[plot_y]])) +
    geom_point() +
    geom_smooth(method = "lm", se = TRUE) +
    theme_minimal() +
    labs(title = paste0(plot_x, " vs ", plot_y), x = plot_x, y = plot_y)
  print(p)
  ggsave(filename = file.path(PLOT_DIR, paste0(plot_x, "_vs_", plot_y, ".png")),
         plot = p, width = 7, height = 5, dpi = 150)
}

# ---- Linear model (lm) ----
# Choose target automatically: prefer 'humidity' if present; else use the last numeric column.
num_cols <- names(num_df)
stopifnot(length(num_cols) >= 2)

if ("humidity" %in% num_cols) {
  target <- "humidity"
} else {
  target <- tail(num_cols, 1)
}

predictors <- setdiff(num_cols, target)
if (length(predictors) < 1) stop("Need at least 1 predictor numeric column")

form <- as.formula(paste(target, "~", paste(predictors, collapse = " + ")))
cat("\nModel formula:", deparse(form), "\n")

fit <- lm(form, data = df)
cat("\n=== lm() Summary ===\n")
print(summary(fit))

# ---- Predictions & metrics ----
df$predicted <- predict(fit, newdata = df)
RMSE <- sqrt(mean((df[[target]] - df$predicted)^2, na.rm = TRUE))
R2   <- cor(df[[target]], df$predicted, use = "complete.obs")^2

cat(sprintf("\nRMSE: %.4f\nR^2:  %.4f\n", RMSE, R2))

# ---- Predicted vs Actual plot ----
pp <- ggplot(df, aes(x = .data[[target]], y = predicted)) +
  geom_point() +
  geom_abline(intercept = 0, slope = 1, linetype = "dashed") +
  theme_minimal() +
  labs(title = paste("Predicted vs Actual:", target), x = paste("Actual", target), y = paste("Predicted", target))
print(pp)

ggsave(filename = file.path(PLOT_DIR, paste0("pred_vs_actual_", target, ".png")),
       plot = pp, width = 7, height = 5, dpi = 150)

# ---- Optional: Train/Test split (holdout) ----
# Uncomment to evaluate more realistically
# set.seed(42)
# idx <- createDataPartition(df[[target]], p = 0.8, list = FALSE)
# train <- df[idx, ]; test <- df[-idx, ]
# fit_tt <- lm(form, data = train)
# preds  <- predict(fit_tt, newdata = test)
# rmse_tt <- sqrt(mean((test[[target]] - preds)^2, na.rm = TRUE))
# r2_tt   <- cor(test[[target]], preds, use = "complete.obs")^2
# cat(sprintf("\nHoldout RMSE: %.4f\nHoldout R^2:  %.4f\n", rmse_tt, r2_tt))

cat("\nDone. Figures saved in ./figs\n")
