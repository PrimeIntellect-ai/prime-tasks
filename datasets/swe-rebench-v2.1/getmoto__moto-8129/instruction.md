[HIDDEN]
## moto==5.0.14

I encountered an error when a dynamodb UpdateItem operation results in a field being deleted from a Map. Here's a test to demonstrate:
```python
from unittest import TestCase

import boto3
from moto import mock_aws


@mock_aws
class TestDeleteEmptyStringSetFromMap(TestCase):
    """
    When you UpdateItem with a DELETE action on an empty string set, DynamoDB should delete the whole field from the Map
    the field is in. In Moto, this produces an AttributeError:

    File ".../python3.12/site-packages/moto/dynamodb/parsing/executors.py", line 194, in execute
        del container[attribute_name]  # type: ignore[union-attr]
            ~~~~~~~~~^^^^^^^^^^^^^^^^
        AttributeError: __delitem__

    You can verify this test passes against AWS by dropping the `@mock_aws` decorator.
    """
    def test_delete_from_empty_string_set(self):
        self._table.put_item(
            Item={
                'pk': 'foo',
                'map': {
                    'stringSet': {'foo'}
                }
            }
        )
        resp = self._table.update_item(
            Key={'pk': 'foo'},
            UpdateExpression='DELETE #map.#stringSet :s',
            ExpressionAttributeNames={
                '#map': 'map',
                '#stringSet': 'stringSet'
            },
            ExpressionAttributeValues={':s': {'foo'}},
            ReturnValues='ALL_NEW'
        )
        self.assertEqual(
            {
                'pk': 'foo',
                'map': {}
            },
            resp['Attributes']
        )


    def setUp(self):
        self._table_name = 'example-test-table'
        self._client = boto3.client('dynamodb')
        self._table = boto3.resource('dynamodb').create_table(
            AttributeDefinitions=[
                {
                    'AttributeName': 'pk',
                    'AttributeType': 'S'
                }
            ],
            TableName=self._table_name,
            KeySchema=[
                {
                    'AttributeName': 'pk',
                    'KeyType': 'HASH'
                }
            ],
            BillingMode='PAY_PER_REQUEST',
        )
        waiter = self._client.get_waiter('table_exists')
        waiter.wait(TableName=self._table_name)

    def tearDown(self):
        self._table.delete()
        waiter = self._client.get_waiter('table_not_exists')
        waiter.wait(TableName=self._table_name)

```

After a quick glance, it looks like this can be resolved by [HIDDEN]
[HIDDEN]

I didn't get set up to run the full moto test suite, but hopefully this is an easy fix for you.

### Additional contract requirements

- When an UpdateItem DELETE removes the last member of a set-valued field nested in a map, the update should succeed and return the item with the map retained and that field absent.
