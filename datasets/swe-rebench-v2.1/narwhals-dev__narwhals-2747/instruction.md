[Enh]: Ability to convert string to date
### We would like to learn about your use case. For example, if this feature is needed  to adopt Narwhals in an open source project, could you please enter the link to it below?


There is ability to convert string into datetime, however, to date is missing, request is to add this feature.

Current work around:
`nw.col("my_col").str.to_datetime(format="%Y%m").cast(nw.Date)`

### Please describe the purpose of the new feature or describe the problem to solve.

To simplify the conversion from string to date without the use of datetime.

### Suggest a solution if possible.

_No response_

### If you have tried alternatives, please describe them below.

`nw.col("my_col").str.to_datetime(format="%Y%m").cast(nw.Date)`

### Additional information that may help us understand your needs.

_No response_

### Additional contract requirements

- Provide direct string-to-date conversion through `.str.to_date(format=...)` for both Series and expressions (for example, `nw.col("my_col").str.to_date(format="%Y%m")`).
- The operation returns Date values without requiring callers to convert through datetime and cast. The `format` argument is optional; when omitted, the backend may infer the format.
