Select multiple dates
**Is your feature request related to a problem? Please describe.**
It's not a problem, it's a use-case. In our platform our users should be able to select multiple dates (not a range, but an array of dates).

**Describe the solution you'd like**
To have an option to select multiple dates.

**Describe alternatives you've considered**
Of course there are other packages we can use but we were thinking about using this package since it looks modern and allows us to get rid of moment.

### Additional contract requirements

Multiple-date selection is enabled with the `selectsMultiple` prop. The currently selected individual dates are supplied as an array of `Date` objects through `selectedDates`. When a user selects another date in this mode, `onChange` receives the updated selection as an array of dates.
