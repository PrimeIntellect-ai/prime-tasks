Date functions should be allowed in where clause
- [ ] Feature
- [x] Bug

<!--If this is a bug, please include the steps to reproduce the bug-->
## Description

Date functions throw and error are not parsed when used in a `WHERE` clause.

https://developer.salesforce.com/docs/atlas.en-us.soql_sosl.meta/soql_sosl/sforce_api_calls_soql_select_date_functions.htm

Example query:
`SELECT Id, convertCurrency(Amount) FROM Opportunity WHERE Amount > 0 AND CALENDAR_YEAR(CloseDate) = 2020`
