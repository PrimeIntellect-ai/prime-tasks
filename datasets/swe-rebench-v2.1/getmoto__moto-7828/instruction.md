DynamoDb transact write items errors for Update expression multiple set action
When using moto mock dynamodb, transact_write_items operation errors even when there is only a single SET action in an update action to dynamo. Error as below

_**botocore.exceptions.ClientError: An error occurred (ValidationException) when calling the TransactWriteItems operation: Invalid UpdateExpression: The "SET" section can only be used once in an update expression;**_

Issue was found in moto 5.0.10.
Reverting back to 5.0.9 works as expected.
