[HIDDEN]
**Describe the bug**
The JSON path expression used to identify the objects in the payload to check for duplicate fields throws an error when it encounters an array. This looks to be an issue in the jsonpath-plus library.

**To Reproduce**
Use the input for #104 (part of the repo now in `valid-parameters-issue104.json` and remove the try/catch added in `mustNotHaveDuplicateFieldNamesAfterEvaluation`

**Expected behavior**
Shouldn't throw a runtime exception from the jsonpath-plus library. Should instead correctly report the payload template as valid or invalid.

**Version:**
3.0.x

**Additional context**
[HIDDEN] There's too much dark magic in the expression evaluation even without this array handling issue.

### Additional contract requirements

- Evaluating payload templates that contain arrays must not throw a jsonpath-plus runtime exception.
- Duplicate field-name conflicts after evaluation, including conflicts nested inside arrays, must be reported as invalid.
