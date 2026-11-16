Pass state fails validation when InputPath is used to access the Context Object
Hello, In August 2020, AWS [released](https://aws.amazon.com/blogs/aws/aws-step-functions-adds-updates-to-choice-state-global-access-to-context-object-dynamic-timeouts-result-selection-and-intrinsic-functions-to-amazon-states-languages/) numerous updates for Step Functions, most of which you support. They added support for accessing the Context Object outside of just Parameters. See https://docs.aws.amazon.com/step-functions/latest/dg/input-output-contextobject.html

When using a Pass State with an InputPath to referencing the $$.Execution.Id the validator returns an error even though this properly deployed and works without issue. I also started an [issue](https://github.com/serverless-operations/serverless-step-functions/issues/402) at serverless-step-functions, but it seems the correct place for this is here. I have tested this InputPath in other states and it seems the same issue exists across the board.

```
definition:
  Comment: "Testing getting Context Object from InputPath in Pass State"
  StartAt: pass-execution-details
  States:
    pass-execution-details:
      Type: Pass
      ResultPath: $.AWS_STEP_FUNCTIONS_STARTED_BY_EXECUTION_ID
      InputPath: $$.Execution.Id
      End: True
```

This fails with:

```
✕ State machine "test-pass-inputpath" definition is invalid:
  undefined: undefined
  No errors
```

The code from [serverless-step-functions](https://github.com/serverless-operations/serverless-step-functions)

```
        if (stateMachineObj.definition) {
          if (this.serverless.service.stepFunctions.validate) {
            const { isValid, errorsText } = aslValidator(stateMachineObj.definition);
            if (isValid) {
              this.serverless.cli.consoleLog(`✓ State machine "${stateMachineName}" definition is valid`);
            } else {
              const errorMessage = [
                `✕ State machine "${stateMachineName}" definition is invalid:`,
                errorsText(),
              ].join('\n');
              throw new this.serverless.classes.Error(errorMessage);
            }
          }
```
