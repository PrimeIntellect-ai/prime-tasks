DynamoDB should return a ValidationError if you try to put an item with an empty string set
## Summary
I recently discovered a difference between moto and DynamoDB behavior - moto will accept an item with an empty String Set, while DynamoDB will return a ValidationError. Here's a quick TestCase to reproduce:

```python
from unittest import TestCase

import boto3
from botocore.exceptions import ClientError
from moto import mock_aws


@mock_aws
class TestEmptyStringSet(TestCase):
    """
    DynamoDB will return a ValidationError, if you try to put an empty string set. This can be confirmed by running this
    test against a real AWS account, without the @mock_aws decorator.
    """
    def test_client_error_on_empty_string_set(self):
        """
        Should raise Client error:
        ```
        botocore.exceptions.ClientError: An error occurred (ValidationException) when calling the PutItem operation: One
        or more parameter values were invalid: An string set  may not be empty
        ```
        """
        with self.assertRaises(ClientError) as e:
            self._client.put_item(
                TableName=self._table_name,
                Item={
                    'pk': {'S': 'foo'},
                    'stringSet': {'SS': []}
                }
            )

        self.assertEqual(e.exception.response['Error']['Code'], 'ValidationException')

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
