ENH: handle NaNs in limit_range
`limit_range` returns an empty array if there's NaN. It should be ignored (maybe add a keyword to control?).
