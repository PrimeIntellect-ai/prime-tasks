[Regression in UpdateItem: Invalid UpdateExpression Error (5.1.2)] - [DynamoDB]: Path overlap check for valid updates
Hi,

After upgrading to `moto` 5.1.2 (PR #8648), I encountered an issue where valid `UpdateItem` operations fail in `moto` with a `ValidationException`, even though they work fine with real DynamoDB tables.

**Expected Behavior**
- The update operation should succeed, as it does on a real DynamoDB table.

**Actual Behavior**
- The update fails in `moto` with the following error:

```plaintext
botocore.exceptions.ClientError: An error occurred (ValidationException) when calling the UpdateItem operation:
Invalid UpdateExpression: Two document paths overlap with each other; must remove or rewrite one of these paths;
path one: [nested], path two: [nested]
```

**Minimal Reproducible Test Case**

```python
import os
from typing import TypeVar, Generator

import boto3
import pytest
from moto import mock_aws
from boto3.session import Session
from mypy_boto3_dynamodb.service_resource import Table, DynamoDBServiceResource

T = TypeVar("T")

YieldFixture = Generator[T, None, None]


@pytest.fixture(scope="session")
def region_name() -> str:
    return "us-east-1"


@pytest.fixture(scope="session")
def aws_credentials(region_name: str):
    """Mocked AWS Credentials for moto."""
    os.environ["AWS_ACCESS_KEY_ID"] = "testing"
    os.environ["AWS_SECRET_ACCESS_KEY"] = "testing"
    os.environ["AWS_SECURITY_TOKEN"] = "testing"
    os.environ["AWS_SESSION_TOKEN"] = "testing"
    os.environ["AWS_DEFAULT_REGION"] = region_name


@pytest.fixture(scope="session")
def dynamodb_resource(aws_credentials, region_name: str) -> YieldFixture[DynamoDBServiceResource]:
    with mock_aws():
        yield boto3.resource(service_name="dynamodb", region_name=region_name)


@pytest.fixture
def moto_dynamodb_table(dynamodb_resource: DynamoDBServiceResource) -> Table:
    return dynamodb_resource.create_table(
        TableName="dev-table",
        KeySchema=[{"AttributeName": "id", "KeyType": "HASH"}],
        AttributeDefinitions=[{"AttributeName": "id", "AttributeType": "S"}],
        BillingMode="PAY_PER_REQUEST",
    )


@pytest.fixture
def real_dynamodb_table() -> Table:
    # This is the real table in the AWS account, need to be created upfront
    return Session(profile_name="<your-valid-profile>").resource("dynamodb").Table("dev-table")


def test_update_item_moto(moto_dynamodb_table: Table):
    nested = {"key1": "value1", "key2": "value2", "key3": "value3"}
    item = {"id": "1", "name": "test", "nested": nested}
    moto_dynamodb_table.put_item(Item=item)
    moto_dynamodb_table.update_item(
        Key={"id": "1"},
        UpdateExpression="SET #BPGKOx.#IMAz=:key1,#BPGKOx.#dCtc=:key2",
        ExpressionAttributeNames={"#BPGKOx": "nested", "#IMAz": "key1", "#dCtc": "key2"},
        ExpressionAttributeValues={":key1": "new value1", ":key2": "new value2"},
    )
    item = moto_dynamodb_table.get_item(Key={"id": "1"})["Item"]
    assert item["nested"] == {"key1": "new value1", "key2": "new value2", "key3": "value3"}


def test_update_item_real(real_dynamodb_table: Table):
    nested = {"key1": "value1", "key2": "value2", "key3": "value3"}
    item = {"id": "1", "name": "test", "nested": nested}
    real_dynamodb_table.put_item(Item=item)
    real_dynamodb_table.update_item(
        Key={"id": "1"},
        UpdateExpression="SET #BPGKOx.#IMAz=:key1,#BPGKOx.#dCtc=:key2",
        ExpressionAttributeNames={"#BPGKOx": "nested", "#IMAz": "key1", "#dCtc": "key2"},
        ExpressionAttributeValues={":key1": "new value1", ":key2": "new value2"},
    )
    item = real_dynamodb_table.get_item(Key={"id": "1"})["Item"]
    assert item["nested"] == {"key1": "new value1", "key2": "new value2", "key3": "value3"}
```

Environment Details

Moto Version: 5.1.2
Python Version: 3.12

Thanks for your time! Let me know if you need any further details. 😊
