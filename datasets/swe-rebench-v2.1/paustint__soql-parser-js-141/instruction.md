Date functions should be allowed in ORDER BY clause
- [ ] Feature
- [x] Bug

## Description
SOQL parser dislikes some functions in 'ORDER BY' and throws the error: "Redundant input, expecting EOF but found: (". Although the query is completely valid: you can execute it in Salesforce developer console and observe, that objects are ordered.

## Steps to reproduce
Execute the following query:
```sql
SELECT WEEK_IN_YEAR(CloseDate), SUM(amount)
FROM Opportunity
GROUP BY WEEK_IN_YEAR(CloseDate)
ORDER BY WEEK_IN_YEAR(CloseDate)
```

## Affected versions
 - **2.5.3**
 - Version used in [demo](https://paustint.github.io/soql-parser-js/): I assume, the latest one (**3.0.1^**) is used there

## Observed behavior
Parser throws "Redundant input, expecting EOF but found: (" for 'WEEK_IN_YEAR' function call in 'ORDER BY' clause

## Expected behavior
Query is parsed and parsing result contains something like this:
```javascript
{
  ...
  "orderBy": {
    "fn": {
      "functionName": "WEEK_IN_YEAR",
      "parameters": [
        "CloseDate"
      ],
      "rawValue": "WEEK_IN_YEAR(CloseDate)"
    },
  ...
}
```
