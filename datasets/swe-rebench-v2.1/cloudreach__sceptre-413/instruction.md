update-stack-cs does not exit with an appropriate return code
The return code for `update-stack-cs` is not consistent with other commands such as `create-stack` or `update-stack`. In the cases where a change-set execution rolls back and leaves the stack in a ROLLBACK_COMPLETE state, `update-stack-cs` should exit with a return code of `1` to indicate a failed execution whereas it currently _always_ exits with a `0`.

## Steps to Reproduce

Create a new stack with a DynamoDB Table resource:

```yaml
Resources:
  myTable:
    Type: AWS::DynamoDB::Table
    Properties:
      TableName: my-dynamodb-table
      AttributeDefinitions:
        - AttributeName: Id
          AttributeType: S
      KeySchema:
        - AttributeName: Id
          KeyType: HASH
      ProvisionedThroughput:
        ReadCapacityUnits: 5
        WriteCapacityUnits: 5
```

Once the stack is deployed successfully, change the table keyschema to use `Id2`. This change requires a table replacement. However, cloudformation will not replace the table since it has a `TableName` property. Attempting to deploy this change will force the stack to a ROLLBACK_COMPLETE state to test this use-case.

```yaml
Resources:
  myTable:
    Type: AWS::DynamoDB::Table
    Properties:
      TableName: my-dynamodb-table
      AttributeDefinitions:
        - AttributeName: Id2
          AttributeType: S
      KeySchema:
        - AttributeName: Id2
          KeyType: HASH
      ProvisionedThroughput:
        ReadCapacityUnits: 5
        WriteCapacityUnits: 5
```

Deploy the changes using `update-stack-cs`. The CLI will exit with a `0` whereas it should be exiting with `1` since the stack is in a ROLLBACK_COMPLETE state.
