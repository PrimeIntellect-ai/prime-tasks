Some date formats are not properly parsed
- [ ] Feature
- [x] Bug

<!--If this is a bug, please include the steps to reproduce the bug-->
## Description
Dates in this format are valid with Salesforce, but not parsed properly: `2020-04-15T02:40:03.000+0000`

Example: `SELECT Id FROM LoginHistory WHERE LoginTime > 2019-04-15T02:40:03.000+0000 AND LoginTime < 2020-04-15T02:40:03.000+0000`
Order By does not allow aggregate queries
- [ ] Feature
- [x] Bug

<!--If this is a bug, please include the steps to reproduce the bug-->
## Description
Salesforce supports aggregate functions in the order by, but parsing fails.
Example query: `SELECT ProductCode FROM Product2 GROUP BY ProductCode HAVING COUNT(Id) > 1 ORDER BY COUNT(Id) DESC`
Functions in order by are not composed correctly
- [ ] Feature
- [x] Bug

<!--If this is a bug, please include the steps to reproduce the bug-->
## Description
If ASC or DESC is included in an order by that uses a function, then the query is not composed properly.
```diff
-SELECT ProductCode FROM Product2 GROUP BY ProductCode HAVING COUNT(Id) > 1 ORDER BY COUNT(Id)DESC
+SELECT ProductCode FROM Product2 GROUP BY ProductCode HAVING COUNT(Id) > 1 ORDER BY COUNT(Id) DESC
```
