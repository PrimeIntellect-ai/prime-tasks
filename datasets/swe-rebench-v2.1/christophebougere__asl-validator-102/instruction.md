Validation error in Parameters for Task type Pass
**Describe the bug**
For State Type Pass it throws validation errror
```
 keyword: 'type',
    dataPath: ".States['EmptyState'].Parameters[0]",
    schemaPath: 'pass.json#/properties/Parameters/items/type',
    params: { type: 'object' },
    message: 'should be object'
```
**To Reproduce**
Please provide a complete state machine definition:
```json
{
  "StartAt": "EmptyState",
  "States": {
    "EmptyState": {
       "Type": "Pass",
      "Parameters": ["abc"],
      "ResultPath": "$.emptyState",
      "End": true
    }
  }
}
```

**Expected behavior**

Parameters can accept ARRAY, NUMBER, BOOLEAN, OBJECT, STRING

**Version:** [e.g. 1.9.4, can be found by running `asl-validator --version`]
2.2.1
**Additional context**
Add any other context about the problem here.

### Additional contract requirements

- For a payload-template format error at `/States/Hello, World/Parameters/lorem.$`, the reported `schemaPath` must be `#/patternProperties/%5E.%2B%5C.%5C%24%24/format`.
