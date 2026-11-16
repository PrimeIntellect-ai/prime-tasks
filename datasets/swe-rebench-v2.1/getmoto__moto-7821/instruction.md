DynamoDB transact write items update throws without expression attribute names
In the latest release 5.0.10, DynamoDB `transact_write_items` update operation fails if `ExpressionAttributeNames` is absent. Works fine with 5.0.9.

Error: `TypeError: 'NoneType' object is not iterable`

[HIDDEN]

Code to reproduce error:
```py
import boto3
from moto import mock_aws

if __name__ == "__main__":
    with mock_aws():
        ddb_client = boto3.client("dynamodb", region_name="us-east-1")
        ddb_client.create_table(
            AttributeDefinitions=[{"AttributeName": "name", "AttributeType": "S"}],
            TableName="test",
            KeySchema=[{"AttributeName": "name", "KeyType": "HASH"}],
            BillingMode="PROVISIONED",
            ProvisionedThroughput={"ReadCapacityUnits": 5, "WriteCapacityUnits": 5},
        )

        ddb_client.transact_write_items(
            TransactItems=[
                {
                    "Update": {
                        "TableName": "test",
                        "Key": {"name": {"S": "test"}},
                        "UpdateExpression": "SET xxx = :xxx",
                        "ConditionExpression": "attribute_not_exists(xxx)",
                        "ExpressionAttributeValues": {":xxx": {"S": "123"}},
                    }
                }
            ]
        )
```
