Add option for "All visits" at "Default interval to load"
#### Summary

I love the option to set the option of what the default scope. But I am missing the option to set it to "All visits" what would be this option:

![image](https://user-images.githubusercontent.com/17692860/134828743-c1b7f666-0674-408e-a495-e72f7fd469db.png)

This atm cant be default, but I´d wish I would set it.

### Additional contract requirements

- The `DateInterval` type exported from `src/utils/dates/types` includes the value `'all'`, representing the "All visits" interval.
- `DateIntervalDropdownItems` (exported from `src/utils/dates/DateIntervalDropdownItems`) accepts an `allText: string` prop in addition to `active?: DateInterval` and `onChange: (interval: DateInterval) => void`. It renders an option for the all interval labelled with `allText`, a divider, and one option for each value in `DATE_INTERVALS`. The option matching the current `active` interval is marked active, and selecting any option, including the all option, calls `onChange` with the selected interval (`'all'` for the all option).
- `DateIntervalSelector` (exported from `src/utils/dates/DateIntervalSelector`) accepts the same `allText: string` prop and uses it as the button label when no interval is active. Its dropdown labels the all option with `allText`, reflects the active interval, and calls the supplied `onChange` when an option is selected.
- In `DateRangeSelector`, the all option is labelled with the selector's `defaultText`, and choosing it selects the all-visits interval.

- When `DateRangeSelector` receives `initialDateRange='all'`, its all-visits option is shown as the active interval.

- Users can choose “All visits” as the default interval in visits settings, and that selection is saved as the default interval.
