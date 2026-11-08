getFlattenedFields returns incorrect results if relationship field is grouped and you are grouping for only one field
- [ ] Feature
- [x] Bug

<!--If this is a bug, please include the steps to reproduce the bug-->
## Description

`getFlattenedFields()` does not return correct fields if a relationship field is used in a group-by.

For the following query, salesforce returns the records with the fields `Name: 'abc', expr0: 1'`

```sql
SELECT Account.Name, AVG(Amount)
FROM Opportunity
GROUP BY Account.Name
LIMIT 5
```

Related #98
