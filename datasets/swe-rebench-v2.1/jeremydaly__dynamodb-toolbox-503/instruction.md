Query Limit is Stringified: Serialization Error (v0.8.1)
In both `queryParams` and `scanParams`, the code is incorrectly stringifying `limit`. As is, with all default configurations, the code throws "SerializationException: STRING_VALUE cannot be converted to Integer".

These are links to the two lines in Table.ts:
https://github.com/jeremydaly/dynamodb-toolbox/blob/30a82ca8839a3afe5660beb863816a48a6b6ab6d/src/classes/Table/Table.ts#L719
https://github.com/jeremydaly/dynamodb-toolbox/blob/30a82ca8839a3afe5660beb863816a48a6b6ab6d/src/classes/Table/Table.ts#L956

I believe the fix is as simple as just [HIDDEN] [HIDDEN] and adjusting the expectations in table.query.unit.test.ts and table.scan.unit.test.ts

### Additional contract requirements

- When a limit is configured, query and scan parameter generation must represent it as a number, not a string.
