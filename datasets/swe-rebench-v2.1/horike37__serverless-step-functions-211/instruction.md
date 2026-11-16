Support `Resource: arn:aws:states:::lambda:invoke`
# This is a Feature Proposal

## Description

With the new [Context Object](https://docs.aws.amazon.com/step-functions/latest/dg/input-output-contextobject.html) it is possible to define a state with a resource of `Resource: arn:aws:states:::lambda:invoke`. This is similar to the callback pattern but without the `.waitForTaskToken` suffix. Specifying the function arn in the `Parmeters.FunctionName` in this way (as opposed to in `Resource`) allows you to then also modify the `Parameters.Payload` property, optionally referencing values from the context object using `$$`.

Example:

```
GetExecutionName:
  Type: Task
  Resource: arn:aws:states:::lambda:invoke
  Parameters:
    FunctionName: arn:aws:lambda:us-east-1:1234123412341234:function:my-service-dev-myFunction
    Payload:
      ExecutionName.$: "$$.Execution.Name"
```

[HIDDEN]

Similar or dependent issues:
* #202

### Additional contract requirements

- When compiling a Task with `Resource: arn:aws:states:::lambda:invoke`, include `lambda:InvokeFunction` permission for the function identified by `Parameters.FunctionName` in the generated execution-role permissions.
