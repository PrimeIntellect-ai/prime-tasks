DynamoDB query with GSI doesn't return LastEvaluatedKey when paging moto 5.0.4 and later
Hi folks,

The failing test is querying with a GSI and pagination.  In this test the `LastEvaluatedKey` is not returned, so in effect doesn't page and return all results.

Found related issues against moto, but none of the fixes seem to work for this specific issue:
* https://github.com/getmoto/moto/issues/7570
* https://github.com/getmoto/moto/issues/7531
* https://github.com/getmoto/moto/issues/7534
* https://github.com/getmoto/moto/issues/7578

I tested all the moto versions and it errors from `5.0.4` onwards:
```
pip install moto[all]==5.0.8 # error
pip install moto[all]==5.0.7 # error
pip install moto[all]==5.0.6 # error
pip install moto[all]==5.0.5 # error
pip install moto[all]==5.0.4 # error
pip install moto[all]==5.0.3 # works
```

Working test `5.0.3`
```
DEBUG    root:test_dynamodb_gsi_pagination_condensed.py:27 last_evaluated_key: {'Artist': {'S': 'Green Day'}, 'SongTitle': {'S': 'song-3'}, 'AlbumTitle': {'S': 'Dookie'}}
DEBUG    root:test_dynamodb_gsi_pagination_condensed.py:27 last_evaluated_key: {'Artist': {'S': 'Green Day'}, 'SongTitle': {'S': 'song-5'}, 'AlbumTitle': {'S': 'Dookie'}}
DEBUG    root:test_dynamodb_gsi_pagination_condensed.py:27 last_evaluated_key: {'Artist': {'S': 'Green Day'}, 'SongTitle': {'S': 'song-7'}, 'AlbumTitle': {'S': 'Dookie'}}
DEBUG    root:test_dynamodb_gsi_pagination_condensed.py:27 last_evaluated_key: {'Artist': {'S': 'Green Day'}, 'SongTitle': {'S': 'song-9'}, 'AlbumTitle': {'S': 'Dookie'}}
DEBUG    root:test_dynamodb_gsi_pagination_condensed.py:27 last_evaluated_key: {'Artist': {'S': 'Green Day'}, 'SongTitle': {'S': 'song-11'}, 'AlbumTitle': {'S': 'Dookie'}}
DEBUG    root:test_dynamodb_gsi_pagination_condensed.py:27 last_evaluated_key: {'Artist': {'S': 'Green Day'}, 'SongTitle': {'S': 'song-13'}, 'AlbumTitle': {'S': 'Dookie'}}
DEBUG    root:test_dynamodb_gsi_pagination_condensed.py:27 last_evaluated_key: {'Artist': {'S': 'Green Day'}, 'SongTitle': {'S': 'song-15'}, 'AlbumTitle': {'S': 'Dookie'}}
DEBUG    root:test_dynamodb_gsi_pagination_condensed.py:27 last_evaluated_key: {'Artist': {'S': 'Green Day'}, 'SongTitle': {'S': 'song-17'}, 'AlbumTitle': {'S': 'Dookie'}}
DEBUG    root:test_dynamodb_gsi_pagination_condensed.py:27 last_evaluated_key: None
DEBUG    root:test_dynamodb_gsi_pagination_condensed.py:28 Retrieved 20 items from dynamodb
```

Not working test `5.0.8`
```
DEBUG    root:test_dynamodb_gsi_pagination_condensed.py:27 last_evaluated_key: None
DEBUG    root:test_dynamodb_gsi_pagination_condensed.py:28 Retrieved 2 items from dynamodb
```

## Test
I'm using `Python 3.12.0`.

To run test:
```
pytest -o log_cli=true ./test_dynamodb_gsi_pagination_condensed.py
```

requirements.txt
```
boto3==1.34.112
botocore==1.34.112
moto[all]==5.0.8
pytest==8.2.1
```

Test code
```python
# pytest -o log_cli=true ./test_dynamodb_gsi_pagination_condensed.py

import os
import logging
import boto3
import pytest
from boto3.dynamodb.types import TypeDeserializer
from moto import mock_aws

logger = logging.getLogger()
logging.basicConfig(
    format="%(asctime)s %(levelname)s - %(name)s %(message)s",
    level=logging.DEBUG,
    force=True,
)
logging.getLogger("boto3").setLevel(logging.WARNING)
logging.getLogger("botocore").setLevel(logging.WARNING)


def query_with_pagination(**kwargs):
    client = boto3.client("dynamodb", region_name="ap-southeast-2")
    response = client.query(**kwargs)
    items = response["Items"]
    last_evaluated_key = response.get("LastEvaluatedKey")
    while last_evaluated_key:
        response = client.query(ExclusiveStartKey=last_evaluated_key, **kwargs)
        items += response["Items"]
        last_evaluated_key = response.get("LastEvaluatedKey")
        logger.debug(f"last_evaluated_key: {last_evaluated_key}")
    logger.debug(f"Retrieved {len(items)} items from dynamodb"),
    return dynamodb_to_python(items) if items else []


def dynamodb_to_python(dynamodb_items: list) -> list:
    return [
        {k: TypeDeserializer().deserialize(v) for k, v in item.items()}
        for item in dynamodb_items
    ]


ACCOUNT_ID, REGION, TABLE_NAME = "123456789012", "ap-southeast-2", "Music"


@pytest.fixture(name="dynamodb_client")
def fixture_dynamodb_client():
    os.environ["AWS_ACCESS_KEY_ID"] = "testing"
    os.environ["AWS_SECRET_ACCESS_KEY"] = "testing"
    os.environ["AWS_SECURITY_TOKEN"] = "testing"
    os.environ["AWS_SESSION_TOKEN"] = "testing"
    os.environ["AWS_DEFAULT_REGION"] = REGION
    with mock_aws():
        yield boto3.client("dynamodb", region_name=REGION)


@mock_aws
def setup_table(dynamodb_client):
    dynamodb_client.create_table(
        AttributeDefinitions=[
            {"AttributeName": name, "AttributeType": "S"}
            for name in ["Artist", "SongTitle", "AlbumTitle"]
        ],
        KeySchema=[
            {"AttributeName": name, "KeyType": type}
            for name, type in [("Artist", "HASH"), ("SongTitle", "RANGE")]
        ],
        GlobalSecondaryIndexes=[
            {
                "IndexName": "AlbumTitleIndex",
                "KeySchema": [{"AttributeName": "AlbumTitle", "KeyType": "HASH"}],
                "Projection": {"ProjectionType": "ALL"},
                "ProvisionedThroughput": {
                    "ReadCapacityUnits": 5,
                    "WriteCapacityUnits": 5,
                },
            }
        ],
        ProvisionedThroughput={"ReadCapacityUnits": 5, "WriteCapacityUnits": 5},
        TableName=TABLE_NAME,
    )
    items = [
        {
            "Artist": {"S": "Green Day"},
            "SongTitle": {"S": f"song-{i}"},
            "AlbumTitle": {"S": "Dookie"},
        }
        for i in range(20)
    ]
    dynamodb_client.batch_write_item(
        RequestItems={TABLE_NAME: [{"PutRequest": {"Item": item}} for item in items]}
    )
    return [f"song-{i}" for i in range(20)]  # for assertion


@mock_aws
def test_query_with_pagination(dynamodb_client):
    query_args = {
        "TableName": TABLE_NAME,
        "IndexName": "AlbumTitleIndex",
        "KeyConditionExpression": "AlbumTitle = :AlbumTitle",
        "ExpressionAttributeValues": {":AlbumTitle": {"S": "Dookie"}},
        "Limit": 2,
    }
    expected_items = setup_table(dynamodb_client)
    items = query_with_pagination(**query_args)
    song_titles = [item["SongTitle"] for item in items]
    assert sorted(song_titles) == sorted(expected_items)
    assert len(song_titles) == len(expected_items)
```

Thanks for your time.
