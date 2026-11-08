Add ovulation display
Mark the days of ovulation on the calendar

### Additional contract requirements

- Add a public function `getOvulationDays(cycles: Cycle[])` in `src/state/CalculationLogics.ts` that returns `string[]`.
- If the array contains fewer than two cycles, it returns an empty array and does not throw.
- For each supplied cycle, return four consecutive dates formatted as `yyyy-MM-dd`. For an effective cycle length `L`, the window starts `L - 16` days after that cycle's `startDate`. If `cycleLength` is zero, use the arithmetic mean of the nonzero `cycleLength` values in the supplied cycles as `L`; truncate a fractional mean toward zero to obtain a whole-day cycle length before calculating the offset.
- For the six-cycle case with 28-day cycles (including `cycles[0].cycleLength === 0`), each supplied cycle's four-day window starts 12 days after its `startDate`. After those windows, six future four-day windows are appended: the first starts 40 days after the first cycle's `startDate`, and each subsequent window starts 28 days after the previous window's start. The windows are returned in this order.
