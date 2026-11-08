PROD ISSUE - Parser is incorrectly categorizing value as geolocation unit
- [ ] Feature
- [x] Bug

<!--If this is a bug, please include the steps to reproduce the bug-->
## Description
Parsing a soql query that contains `'MI' or 'KM'` as a value is incorrectly being categorized as a geolocation unit instead of a string literal.

Steps -
- Parse this query `SELECT State_Abbr_c FROM Contact WHERE State_Abbr_c = 'MI'`
- The `MI` token is being categorized as a geolocation unit instead of a string literal which is throwing an error.
![Screenshot from 2022-06-09 15-59-08](https://user-images.githubusercontent.com/59818977/173181826-60d254ab-204c-4d6e-9ac4-6bb3c360a5bb.png)
