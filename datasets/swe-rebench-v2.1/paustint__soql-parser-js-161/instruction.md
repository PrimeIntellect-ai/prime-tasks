getFlattenedFields does not work correctly on aliased normal fields
- [ ] Feature
- [x] Bug

<!--If this is a bug, please include the steps to reproduce the bug-->
## Description

```sql
SELECT Count(Id), Name account_name
FROM Account
GROUP BY Name
```

Expected fields: `expr0` and  `account_name`
Actual fields: `expr0` and  `Name`
