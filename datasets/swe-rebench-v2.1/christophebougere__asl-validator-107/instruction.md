null is no longer a valid ResultPath
**Describe the bug**
`"ResultPath": null` [is used for discarding the output of a state](https://docs.aws.amazon.com/step-functions/latest/dg/input-output-resultpath.html#input-output-resultpath-null). Since upgrading to 3.0.2, schema validation is now failing with:
``` javascript
[
  {
    'Error code': 'SCHEMA_VALIDATION_FAILED',
    Message: '/States/Hello/ResultPath is invalid. must be string',
    schemaError: {
      instancePath: '/States/Hello/ResultPath',
      schemaPath: 'paths.json#/definitions/asl_ref_path/type'
    }
  }
]
```

**To Reproduce**
```json
{
    "StartAt": "Hello",
    "States": {
        "Hello": {
            "Type": "Task",
            "Resource": "arn:aws:lambda:us-east-1:123456789012:function:foo",
            "Parameters": {
                "foo.$": "$.foo"
            },
            "ResultPath": null,
            "Next": "Goodbye"
        },
        "Goodbye": {
            "Type": "Succeed"
        }
    }
}
```

**Expected behavior**

`null` is accepted as a valid ResultPath.

**Version:**
3.0.2
