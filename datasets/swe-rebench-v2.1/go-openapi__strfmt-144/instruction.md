Parse negative special durations as negative durations
Simply put, if you parse `strfmt.ParseDuration("-1h")`, you will correctly get minus 1 hour. However, when using the "enhanced" durations like `d`/`w`, you will not get a negative duration, but a positive one. So `strfmt.ParseDuration("-1d")` will result in a _positive_ day duration.
