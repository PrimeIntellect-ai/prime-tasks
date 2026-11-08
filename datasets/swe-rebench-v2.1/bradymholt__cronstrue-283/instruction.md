multiple Days of Week with hashtags is outputting null
**Cron string:**
`0 0 * * 0#1,0#2`

**Expected Output:**
```
At 12:00 AM, on the 1st Sunday and 2nd Sunday of the month
```
**Actual Output:**
```
At 12:00 AM, on the null Sunday and Sunday of the month
```

### Additional contract requirements

- The ordinal prefix for a `#` modifier is rendered as a word (`first`, `second`, `third`, `fourth`, `fifth`), consistent with the existing output for a single `#` modifier. The example above therefore produces `At 12:00 AM, on the first Sunday and second Sunday of the month`.
