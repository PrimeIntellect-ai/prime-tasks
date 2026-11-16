Question / feature request: Excel - format as date
I can feed a tablib cell a datetime, and formatting that cell as date in Excel works - the number shown initially gets converted to a valid date.

Can i tell tablib to format the cell as datetime right away, so the Excel file shows date formatting right after being opened?

(Looks like XlsxWriter and xlwt can do that, but i'm reluctant to switch.)

### Additional contract requirements

- When exporting to XLS, format date values with `m/d/yy`, time values with `h:mm:ss`, and datetime values with `m/d/yy h:mm`.
