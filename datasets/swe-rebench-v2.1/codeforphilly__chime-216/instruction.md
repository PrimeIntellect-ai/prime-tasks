[bug] Incorrect doubling time for social distancing values above 63%
### STR
1. Load CHIME (https://penn-chime.phl.io/)
2. Set `Social distancing (% reduction in social contact)` to a value below 64 while leaving other values at the default.
2. Repeat step 2 with a value above 63

### Observed
Doubling times are negative when the social distancing value is greater than 63%

Social Distancing (%) | Doubling Time (days) | Rt
-- | -- | --
0 | 6 | 2.71
25 | 9.7 | 2.04
50 | 27.5 | 1.36
60 | 113.5 | 1.09
63 | 2229.4 | 1
64 | -425.4 | 0.98

### Expected
Doubling times are always positive. When `Rt < 1`, unit of time should still be positive and the summary text should indicate that infections will halve over the period of time, not double.

### Additional contract requirements

- The mitigation summary must include `outbreak **reduces the doubling time to 7.8** days` for the default inputs and `outbreak **halves the infections every 51.9** days` for the tested case with `Rt < 1`.
