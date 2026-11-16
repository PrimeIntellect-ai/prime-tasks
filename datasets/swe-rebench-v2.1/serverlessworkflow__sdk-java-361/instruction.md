Retry definition validation doesn't work
**Given**:
Workflow definition to be validated

```json
{
  "id": "workflow_1",
  "name": "workflow_1",
  "description": "workflow_1",
  "version": "1.0",
  "specVersion": "0.8",
  "start": "Task1",
  "functions": [
    {
      "name": "increment",
      "type": "custom",
      "operation": "worker"
    }
  ],
  "retries": [
    {
      "maxAttempts": 3
    }
  ],
  "states": [
    {
      "name": "Task1",
      "type": "operation",
      "actionMode": "sequential",
      "actions": [
        {
          "functionRef": {
            "refName": "increment",
            "arguments": {
              "input": "some text"
            }
          },
          "retryRef": "const",
          "actionDataFilter": {
            "toStateData": "${ .result }"
          }
        }
      ],
      "end": true
    }
  ]
}
```

**Expected result:**
Validation failed (because of `name` of `RetryDefinition` missed)

**Actual result:**
Validation passed.

The same result(validation passed) if 'name' field is empty or/and `maxAttempts` not defined.
According to specification 'name ' is required and `maxAttempts` not.
But in the `retrydef.json` schema they are required both.

Could you please support us in this question? May be we miss something?

### Additional contract requirements

- Validation is performed through `io.serverlessworkflow.validation.WorkflowValidatorImpl`, which implements `io.serverlessworkflow.api.interfaces.WorkflowValidator` and exposes `setSource(String source)` (returning the same validator instance) and `validate()` (returning a `java.util.List<io.serverlessworkflow.api.validation.ValidationError>`).
- When a retry definition has no name (missing or empty) and an operation state action's `retryRef` does not reference an existing workflow retry definition, the errors returned by `validate()` must include, in this order, the messages "Retry name should not be empty" and "Operation State action 'null' retryRef does not reference an existing workflow retry definition".
