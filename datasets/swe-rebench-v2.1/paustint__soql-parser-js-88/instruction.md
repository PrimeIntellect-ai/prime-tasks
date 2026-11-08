If an empty orderby array is included, the composed query is invalid
<!--
  Please include the following classification.
  If your classification is not added, you can modify the list below
-->
- [ ] Feature
- [x] Bug Request

<!--If this is a bug, please include the steps to reproduce the bug-->
## Description
If an empty array is provided when composing a query, then `ORDER BY` should be omitted from the query.

The following query results in an invalid generated query:

```json
{
  "fields": [
    {
      "type": "Field",
      "field": "Id"
    }
  ],
  "sObject": "Account",
  "orderBy": [],
  "limit": 1,
  "offset": 5
}
```

```sql
SELECT Id
FROM Account
ORDER BY
LIMIT 1
OFFSET 5
```
