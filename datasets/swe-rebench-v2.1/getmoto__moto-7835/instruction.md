DynamoDB sorts by Table hash before GSI when comparing ExclusiveStartKey
When querying using a GSI for items that sort in one direction by the GSI's sort key and in the opposite direction by the table's hash key it appears that the hash key sort takes precedence when comparing whether the item has already been seen (comparing with the ExclusiveStartKey).

It appears that this comes from https://github.com/getmoto/moto/blob/1c8c0fe4d9c7f5481a40814a8a6459a5142707ff/moto/dynamodb/models/table.py#L1035 the change around which was introduced in https://github.com/getmoto/moto/pull/7795

A test which demonstrates this is below, the 2 items are sorted in one direction by their table's hash key, but in the opposite direction by their GSI key (same hash value, different sort values).

```
@mock_aws
def test_query_gsi_pagination_with_string_gsi_range_with_opposite_sort():
    dynamodb = boto3.resource("dynamodb", region_name="us-east-1")

    # Create the DynamoDB table.
    dynamodb.create_table(
        TableName="users",
        KeySchema=[
            {"AttributeName": "pk", "KeyType": "HASH"},
        ],
        AttributeDefinitions=[
            {"AttributeName": "pk", "AttributeType": "S"},
            {"AttributeName": "gsi_hash", "AttributeType": "S"},
            {"AttributeName": "gsi_sort", "AttributeType": "S"},
        ],
        ProvisionedThroughput={"ReadCapacityUnits": 5, "WriteCapacityUnits": 5},
        GlobalSecondaryIndexes=[
            {
                "IndexName": "gsi",
                "KeySchema": [
                    {"AttributeName": "gsi_hash", "KeyType": "HASH"},
                    {"AttributeName": "gsi_sort", "KeyType": "RANGE"},
                ],
                "Projection": {"ProjectionType": "ALL"},
            }
        ],
    )
    table = dynamodb.Table("users")

    table.put_item(Item={"pk": "b", "gsi_hash": "a", "gsi_sort": "a"})
    table.put_item(Item={"pk": "a", "gsi_hash": "a", "gsi_sort": "b"})

    page1 = table.query(
        KeyConditionExpression=Key("gsi_hash").eq("a"),
        IndexName="gsi",
        Limit=1,
    )
    assert page1["Count"] == 1
    assert page1["ScannedCount"] == 1
    assert len(page1["Items"]) == 1

    page2 = table.query(
        KeyConditionExpression=Key("gsi_hash").eq("a"),
        IndexName="gsi",
        Limit=1,
        ExclusiveStartKey=page1["LastEvaluatedKey"],
    )
    assert page2["Count"] == 1 # <------------------------------ fails here
    assert page2["ScannedCount"] == 1
    assert len(page2["Items"]) == 1
    assert "LastEvaluatedKey" not in page2

    results = page1["Items"] + page2["Items"]
    subjects = set([(r["pk"]) for r in results])
    assert subjects == ["b", "a"]
```

[HIDDEN]

Python version 3.11
Latest moto (cloned repo and added test into tests directly, hoping I could figure out a fix if my understanding of the expected behaviour was right)

### Additional contract requirements

- When querying a GSI, items with identical GSI key values must be ordered by the table’s primary key: the table hash key first, then the table sort key if present.
