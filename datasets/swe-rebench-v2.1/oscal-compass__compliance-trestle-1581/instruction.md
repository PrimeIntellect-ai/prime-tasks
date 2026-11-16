trestle task csv-to-oscal-cd should give better error message when set parameter fails
## Issue description / feature objectives

Below is the current error issued by the trestle task when a invalid set parameter cell is encountered. This can be re-created by having a value with blanks, for example `Cloud Network Interfaces count`, in the column` Parameter_Value_Default`.

```
trestle.tasks.csv_to_oscal_cd:293 ERROR: Traceback (most recent call last):
  File "/home/degenaro/git/trestle.develop/trestle/tasks/csv_to_oscal_cd.py", line 672, in _create_set_parameters
    set_parameter = SetParameter(
  File "pydantic/main.py", line 341, in pydantic.main.BaseModel.__init__
pydantic.error_wrappers.ValidationError: 1 validation error for SetParameter
param-id
  string does not match regex "^[_A-Za-z\u00C0-\u00D6\u00D8-\u00F6\u00F8-\u02FF\u0370-\u037D\u037F-\u1FFF\u200C-\u200D\u2070-\u218F\u2C00-\u2FEF\u3001-\uD7FF\uF900-\uFDCF\uFDF0-\uFFFD][_A-Za-z\u00C0-\u00D6\u00D8-\u00F6\u00F8-\u02FF\u0370-\u037D\u037F-\u1FFF\u200C-\u200D\u2070-\u218F\u2C00-\u2FEF\u3001-\uD7FF\uF900-\uFDCF\uFDF0-\uFFFD\-\.0-9\u00B7\u0300-\u036F\u203F-\u2040]*$" (type=value_error.str.regex; pattern=^[_A-Za-z\u00C0-\u00D6\u00D8-\u00F6\u00F8-\u02FF\u0370-\u037D\u037F-\u1FFF\u200C-\u200D\u2070-\u218F\u2C00-\u2FEF\u3001-\uD7FF\uF900-\uFDCF\uFDF0-\uFFFD][_A-Za-z\u00C0-\u00D6\u00D8-\u00F6\u00F8-\u02FF\u0370-\u037D\u037F-\u1FFF\u200C-\u200D\u2070-\u218F\u2C00-\u2FEF\u3001-\uD7FF\uF900-\uFDCF\uFDF0-\uFFFD\-\.0-9\u00B7\u0300-\u036F\u203F-\u2040]*$)
```
An improved error message might look like:

```
[HIDDEN]
```
## Caveats / Assumptions

Code fix might look like:

![image](https://github.com/oscal-compass/compliance-trestle/assets/520029/4822b780-7f8b-4534-b017-7ea5a93460d3)


## Completion Criteria

- Improved error message is provided.
- Test case coverage.

### Additional contract requirements

- When a set parameter cell holds an invalid value (for example, a Parameter_Id containing blanks), executing the task must report failure (the task outcome is `failure`), and the error log for that failure must include a diagnostic that identifies:
  - the CSV row of the offending entry, numbered as it appears in the CSV file with the header line counted as row 1,
  - the Parameter_Id value,
  - the offending Parameter_Value_Default value, and
  - the names of the Parameter_Id and Parameter_Value_Default columns.
