getFlattenedFields does not return accurate resulte when nested aggregate function
- [ ] Feature
- [x] Bug

<!--If this is a bug, please include the steps to reproduce the bug-->
## Description

If an aggregate function is nested within a FORMAT() call, `getFlattenedFields` does not return the correct field value.

```sql
SELECT COUNT(Id), FORMAT(MAX(CreatedDate)), Email
FROM Contact
GROUP BY Email
HAVING COUNT(Id) >= 0
```

`CreatedDate` is returned when it should actually be `expr1`
