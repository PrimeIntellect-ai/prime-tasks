DynamoDB pagination not returning correct results for GSI when table has no range key
This is very similar to #7761 and perhaps related to #7751 but I'm finding that I get incorrect results when using pagination on a DynamoDB table that does not have a range key, when querying a GSI.

To illustrate, I've tweaked the existing test_query_gsi_pagination_with_string_gsi_range to remove the range key. This new test is failing in the latest master version (4c99cbbb), returning no results in the second query - it should return the remaining four:

```
@pytest.mark.aws_verified
@dynamodb_aws_verified(add_range=False, add_gsi_range=True)
def test_query_gsi_pagination_with_string_gsi_range_no_sk(table_name=None):
    dynamodb = boto3.resource("dynamodb", region_name="us-east-1")
    table = dynamodb.Table(table_name)

    for i in range(3, 7):
        table.put_item(
            Item={"pk": f"{i}", "gsi_pk": "john", "gsi_sk": "jane"}
        )

    for i in range(9, 6, -1):
        table.put_item(
            Item={"pk": f"{i}", "gsi_pk": "john", "gsi_sk": "jane"}
        )

    for i in range(3):
        table.put_item(
            Item={"pk": f"{i}", "gsi_pk": "john", "gsi_sk": "jane"}
        )

    page1 = table.query(
        KeyConditionExpression=Key("gsi_pk").eq("john"),
        IndexName="test_gsi",
        Limit=6,
    )
    assert page1["Count"] == 6
    assert page1["ScannedCount"] == 6
    assert len(page1["Items"]) == 6

    page2 = table.query(
        KeyConditionExpression=Key("gsi_pk").eq("john"),
        IndexName="test_gsi",
        Limit=6,
        ExclusiveStartKey=page1["LastEvaluatedKey"],
    )
    assert page2["Count"] == 4
    assert page2["ScannedCount"] == 4
    assert len(page2["Items"]) == 4
    assert "LastEvaluatedKey" not in page2

    results = page1["Items"] + page2["Items"]
    subjects = set([int(r["sk"]) for r in results])
    assert subjects == set(range(10))
```
