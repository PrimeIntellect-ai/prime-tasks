DynamoDB: delete_item does not handle ReturnValuesOnConditionCheckFailure
This issue is very related to #6949

Just like `put_item` and `update_item`, `delete_item` accepts a `ReturnValuesOnConditionCheckFailure` parameter.

When this is set to `ALL_OLD`, a `ConditionalCheckFailedException` should include the `Item` key with the conflicting item.

In other words, the following should work:

```python
import boto3
from moto import mock_aws

with mock_aws():
    client = boto3.client("dynamodb")
    client.create_table(
        TableName="test",
        KeySchema=[{"AttributeName": "Key", "KeyType": "HASH"}],
        AttributeDefinitions=[{"AttributeName": "Key", "AttributeType": "S"}],
        BillingMode="PAY_PER_REQUEST",
    )
    client.put_item(TableName="test", Item={"Key": {"S": "foo"}, "Other": {"N": "42"}})
    try:
        client.delete_item(
            TableName="test",
            Key={"Key": {"S": "foo"}},
            ConditionExpression="#O <> :o",
            ExpressionAttributeNames={"#O": "Other"},
            ExpressionAttributeValues={":o": {"N": "42"}},
            ReturnValuesOnConditionCheckFailure="ALL_OLD",
        )
    except client.exceptions.ConditionalCheckFailedException as exc:
        assert "Item" in exc.response
```

This fails with an `AssertionError` on Python 3.12.3 with moto 5.0.16
