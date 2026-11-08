Timeslice operator
See https://github.com/rcoh/angle-grinder/commit/274d34233bec9fd78ae680651efa58ad13b2a2e0 for a template
A non trivial undertaking. My suggested path:
- [ ] Add a `date` subtype to `data::Value` -- this will include the date rendering logic
- [ ] Add a parseDate expression that produces a `date` value from a string
- [ ] Create the timeslice operator that accepts an `Expression<Date>` as an argument and does the bucketing (nontrivial)
- [ ] Add an automatic `sort by _timeslice` automatically after groupingby `_timeslice`

Proposed query structure:
```* | parse "* * *" as level, date, message | timeslice(parseDate(level)) 5m | count by _timeslice```

### Additional contract requirements

- The automatic sort by `_timeslice` must be ascending.
