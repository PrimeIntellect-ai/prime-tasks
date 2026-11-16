Make availability to hide column from MUIDataTableViewCol, but show in table
## Expected Behavior
It will be a good idea to hide column from View Columns menu, and always show it in table itself.

## Current Behavior
We can't provide an option for columns property not to show column in View Columns menu.

### Additional contract requirements

A column definition may set the per-column option `viewColumns: false` to omit that column's control from the View Columns menu. Other columns remain available in that menu, and the omitted column remains displayed in the table. When the option is not false, the column remains available in the menu.
