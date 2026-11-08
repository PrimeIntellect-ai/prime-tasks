Improve error message for code caret rule on ValueSet compose component without any concept
When writing rules for a ValueSet, it is invalid to make a code caret rule on a concept that is not specifically present within the ValueSet.. However, when there are _no_ specific concepts present, a slightly strange error message is produced.

Sample FSH:
```
ValueSet: SomeVS
* include codes from system http://example.org/CS
* http://example.org/CS#"some-code" ^designation.value = "some value"
```

Error message received:
```
error The element or path you referenced does not exist: compose.include[0].concept[undefined].designation.value
  Line: 3
```
The rule path in the error message is the path constructed within the ValueSetExporter for the rule on line 3. But, it might be more useful to directly indicate that the rule is invalid because there is no concept array in the compose element with `http://example.org/CS` as the system.

### Additional contract requirements

- For the sample rule above, the error message must be exactly: `Cannot process caret assignment rule for code http://example.org/CS#"some-code" because this value set does not explicitly include or exclude this code in its rules. To fix this error, add a rule that specifically includes or excludes this code for the value set.`
