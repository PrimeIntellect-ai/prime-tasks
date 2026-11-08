Duplicate state name is not caught during validation
**Describe the bug**
State names must be unique within the scope of the whole state machine.

**To Reproduce**
PR is inbound w/ a test
```json
{
  "Comment": "Exhibits duplicate state error. State names MUST be unique within the scope of the whole state machine.",
  "StartAt": "Map",
  "States": {
    "Map": {
      "Type": "Map",
      "Next": "Final State",
      "InputPath": "$.input",
      "ItemsPath": "$.items",
      "MaxConcurrency": 0,
      "Iterator": {
        "StartAt": "Final State",
        "States": {
          "Final State": {
            "Type": "Wait",
            "Seconds": 20,
            "End": true
          }
        }
      },
      "ResultPath": "$.result"
    },
    "Final State": {
      "Type": "Pass",
      "End": true
    }
  }
}
```

**Expected behavior**
Report an error

**Version:**
2.0.0

**Additional context**
