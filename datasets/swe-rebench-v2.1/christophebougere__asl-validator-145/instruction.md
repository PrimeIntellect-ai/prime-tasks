[HIDDEN]
**Describe the bug**
The validator fails to emit an error for the Variable expression when it's not a reference path. [HIDDEN]


**To Reproduce**
I can do a PR for this with a full example but here's a snippet:

```json
            "Choices": [
              {
                "Variable": "States.ArrayContains($.clients.unique, 'null')",
                "BooleanEquals": true,
                "Next": "Use Array Length Minus One"
              }
            ],
```

**Expected behavior**
Report an error that the `Variable` field must be a valid reference path.  The expression provided in this example is an intrinsic function but that's not available in this context. It must be a reference path.

**Version:**
3.x
