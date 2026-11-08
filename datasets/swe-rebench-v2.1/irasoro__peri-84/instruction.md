Move all calculation logic to a separate module
As it was written here https://github.com/IraSoro/peri/issues/63#issuecomment-1613810939, we run into the limitation that all necessary calculations are carried out to react hooks, due to which ordinary arithmetic unit tests turn into UI tests

This can be fixed by moving all the calculations to a separate module file, and leaving the hooks as a wrapper for react

### Additional contract requirements

The calculation functions must be exported from the module `src/state/CalculationLogics`:

- `getOvulationStatus(cycleLength: number, dayOfCycle: number): string` — returns an empty string when either argument is missing or zero. Otherwise, with the ovulation day defined as `cycleLength - 14`, it returns `"today"` when the current day equals the ovulation day, `"tomorrow"` when the ovulation day is one day later, `"possible"` when the ovulation day is one or two days earlier, `"finished"` when it is more than two days earlier, and otherwise a localized `"in X Days"` string (with pluralisation) for the remaining days.
- `getPregnancyChance(cycleLength: number, dayOfCycle: number): string` — returns an empty string when either argument is missing or zero; returns `"high"` when the difference between the ovulation day (`cycleLength - 14`) and the current day is between -2 and 4 inclusive, and `"low"` otherwise.
- `getDayOfCycle(startDate: string): string` — returns an empty string for an empty start date; otherwise returns the number of days since `startDate` (inclusive) as a string.
- `getAverageLengthOfCycle(cycles: Cycle[]): number` — returns 0 for an empty array, the single cycle's `cycleLength` for one element, and otherwise the rounded mean of all `cycleLength` values except the first.
- `getAverageLengthOfPeriod(cycles: Cycle[]): number` — returns 0 for an empty array, the single cycle's `periodLength` for one element, and otherwise the rounded mean of all `periodLength` values except the first.
- `getDaysBeforePeriod(cycleLength: number, startDate: string): { title: string; days: string }` — returns `{ title: <localized "Period in">, days: <localized "no info"> }` when either argument is falsy; otherwise `title` is a localized label (`"Period in"`, `"Period"` or `"Delay"`) and `days` is a localized day count (e.g. `"10 Days"`, with pluralisation).
- `getPhase(lengthOfCycle: number, lengthOfPeriod: number, currentDay: number): { title: string; description: string; symptoms: string[] }` — returns a generic non-phase object when any argument is falsy; otherwise, with the ovulation day defined as `lengthOfCycle - 14`, it returns the menstrual phase when `currentDay <= lengthOfPeriod`, the follicular phase when `currentDay <= ovulationDay - 3`, the ovulation phase when `currentDay <= ovulationDay`, and the luteal phase otherwise.

The `Cycle` type is exported from `src/data/ClassCycle` with fields `cycleLength: number`, `periodLength: number` and `startDate: string`.
