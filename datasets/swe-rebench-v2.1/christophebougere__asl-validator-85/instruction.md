nested maps generate an error due to bad path expression in validator
**Describe the bug**
I'm getting this error with an ASL with a nested map.

```
Parse error on line 1:
    $.['Next','Default']
```

It's due to the newly merged state-transitions.js code.

**To Reproduce**
Please provide a complete state machine definition:
```json
{
  "StartAt": "Map",
  "States": {
    "Map": {
      "Type": "Map",
      "Next": "Final State",
      "Iterator": {
        "StartAt": "Map2",
        "States": {
          "Map2": {
            "Type": "Map",
            "End": true,
            "Iterator": {
              "StartAt": "Wait 20s",
              "States": {
                "Wait 20s": {
                  "Type": "Wait",
                  "Seconds": 20,
                  "End": true
                }
              }
            }
          }
        }
      }
    },
    "Final State": {
      "Type": "Succeed"
    }
  }
}
```

**Expected behavior**
no error

**Version:** 2.1.0

**Additional context**
I was missing a test case for a nested map so it wasn't hitting this path in the code. The migration to jsonpath-plus will fix this but it could also be fixed with the existing `jsonpath` library.
