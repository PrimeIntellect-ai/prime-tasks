statemachine.describe_state_machine returning error for a version ARN

When running the following sequence under moto 5.0.25:
```python
import boto3
client = boto3.client("stepfunctions", region_name='us-west-2)
client.create_state_machine(
            name='somestatemachine',
            definition=json.dumps({}),
            roleArn=<role arn>,
            type="STANDARD",
            publish=True,
        )
version_arn = res["stateMachineVersionArn"]
```
Followed by this call:
```python
client.describe_state_machine(stateMachineArn=version_arn)
```
I received the error:
```
botocore.errorfactory.StateMachineDoesNotExist: An error occurred (StateMachineDoesNotExist) when calling the DescribeStateMachine operation: State Machine Does Not Exist: 'arn:aws:states:us-west-2:123456789012:stateMachine:pytest-test-create-sm:1'
```
But if I call `describe_state_machine` without the version_arn and just use the non-versioned arn, the call will succeed.

Based on the docs here: https://boto3.amazonaws.com/v1/documentation/api/1.35.8/reference/services/stepfunctions/client/describe_state_machine.html
```
stateMachineArn (string) –

[REQUIRED]

The Amazon Resource Name (ARN) of the state machine for which you want the information.

If you specify a state machine version ARN, this API returns details about that version. The version ARN is a combination of state machine ARN and the version number separated by a colon (:). For example, stateMachineARN:1.`
```
The expectation is that when a version_arn is passed the version specific details would be returned.
