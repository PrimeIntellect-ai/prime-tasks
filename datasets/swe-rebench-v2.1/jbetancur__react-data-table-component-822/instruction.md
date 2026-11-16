Radio selection for selectableRows
## Feature Check list

- [x] Agree to the [Code of Conduct](https://github.com/jbetancur/react-data-table-component/blob/master/CODE-OF-CONDUCT.md)
- [x] Read the README to ensure the feature is not already present
- [x] You read [Creating Issues, Features and Pull Requests](https://github.com/jbetancur/react-data-table-component/issues/387)
- [x] Considered the value versus complexity for all users of the library as well as library maintenance
- [x] Considered if this can be a storybook or documentation example

## Is your feature request related to a problem? Please describe

Not a problem

## Describe the solution you'd like

Make it possible to enable radio selectable rows. Something similar to this https://www.lightningdesignsystem.com/components/data-tables/#Single-row-selection

## Describe alternatives you've considered

Could probably work something with selectableRowsComponent, but I think this should be easier then that.

## Additional context

No

### Additional contract requirements

- Radio selectable rows are enabled through the existing `selectableRowsComponentProps` prop by passing `{ type: 'radio' }` together with `selectableRows`. When enabled, each row renders a radio control (`type="radio"`) instead of a checkbox.
- With `selectableRowsSingle`, at most one row is selected at a time. Selecting a different row replaces the previous selection, and clicking the currently selected row deselects it so that no row remains selected.


- - Each row selection input must have the name `select-row-${rowKey}` (for example, `select-row-1` and `select-row-2`).
