ValidationException not detected on DynamoDB query
### Bug description

Making a query to a DynamoDB Table Index with two different key values throws the following error:

```
botocore.exceptions.ClientError: An error occurred (ValidationException) when calling the Query operation: Query key condition not supported
```

However, if the same query is made against a mocked environment with `moto` this exception is never raised.

To test this behavior, I used the following script (comment the the `mock_aws` statement to execute against AWS):

```py
import boto3
from moto import mock_aws

table_name = 'Threads'
forum_name = 'ForumName'
subject = 'Subject'
author = 'Author'
index_name = 'Author'
table_definition = {
    "AttributeDefinitions": [
        {
            'AttributeName': forum_name,
            'AttributeType': 'S'
        },
        {
            'AttributeName': subject,
            'AttributeType': 'S'
        },
        {
            'AttributeName': author,
            'AttributeType': 'S'
        }
    ],
    "TableName": table_name,
    "KeySchema": [
        {
            'AttributeName': forum_name,
            'KeyType': 'HASH'
        },
        {
            'AttributeName': subject,
            'KeyType': 'RANGE'
        }
    ],
    "GlobalSecondaryIndexes": [
        {
            'IndexName': index_name,
            'KeySchema': [
                {
                    'AttributeName': author,
                    'KeyType': 'HASH'
                }
            ],
            'Projection': {
                'ProjectionType': 'ALL'
            }
        }
    ],
    "BillingMode": 'PAY_PER_REQUEST',
}


@mock_aws
def create_load_query_delete(deleteTable=False):
    ddb_client = boto3.client("dynamodb")

    try:
        ddb_client.create_table(**table_definition)
        waiter = ddb_client.get_waiter('table_exists')
        waiter.wait(TableName=table_name)
    except ddb_client.exceptions.ResourceInUseException:
        print("Table exists not creating.")

    ddb_client.put_item(
        TableName=table_name,
        Item={
            forum_name: {'S': 'forum1'},
            subject: {'S': 'subject1'},
            author: {'S': 'author1'}
        }
    )

    ddb_client.put_item(
        TableName=table_name,
        Item={
            forum_name: {'S': 'forum1'},
            subject: {'S': 'subject2'},
            author: {'S': 'author2'}
        }
    )

    query_args = {
        'TableName': table_name,
        'IndexName': index_name,
        'KeyConditionExpression': f'{author} = :author AND {subject} = :subject',
        'ExpressionAttributeValues': {
            ':author': {
                'S': 'author1'
            },
            ':subject': {
                'S': 'subject1'
            }
        }
    }

    response = ddb_client.query(**query_args)
    items = response.get('Items', [])

    if deleteTable:
        ddb_client.delete_table(TableName=table_name)

    return items


def test_query():
    assert len(create_load_query_delete(deleteTable=True)) == 1

```

### Environment details

- **moto**: 5.0.28
- **boto3**: 1.36.26
- **python**: 3.12.9
- **OS**: Ubuntu 22.04.5 LTS

### Additional contract requirements

For the query in the reproduction, the expected behavior is a DynamoDB ValidationException with the message "Query key condition not supported": the condition uses `Subject` even though the selected `Author` index does not have `Subject` in its key schema. The reproduction’s final assertion that one item is returned is inconsistent with the reported AWS behavior and is not an expected successful result.
