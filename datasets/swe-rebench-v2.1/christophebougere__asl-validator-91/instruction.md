loc.indexOf is not a function (jsonpath-plus regression)
**Describe the bug**
2.2.0 with jsonpath-plus introduced a regression where an `OutputPath` like `$[(@.length-1)].bar` throws an error.

Same state machine definition passes validation in <2.2.0 and works in Step Functions.

**To Reproduce**
```json
{
  "StartAt": "map",
  "States": {
    "map": {
      "Type": "Map",
      "End": true,
      "InputPath": "$",
      "ItemsPath": "$.foo",
      "Parameters": {
        "bar.$": "$"
      },
      "Iterator": {
        "StartAt": "pass",
        "States": {
          "pass": {
            "Type": "Pass",
            "End": true
          }
        }
      },
      "ResultPath": "$",
      "OutputPath": "$[(@.length-1)].bar"
    }
  }
}
```

**Expected behavior**
This is a valid state machine, it should not error out with `loc.indexOf is not a function`.

**Version:** 2.2.0
