Rule Sets with Value Set Rules Generates errors
Testing `insert` rules with value sets. SUSHI generates errors that indicate the RuleSet is being interpreted as a CodeSystem:
```
RuleSet: Hands
* $SCT#87683000  "Left handed (finding)"
```
Results in:
`error Do not include the system when listing concepts for a code system.`

https://fshschool.org/FSHOnline/#/share/3i4Mc5w

### Additional contract requirements

- When a system-less `ConceptRule` from a RuleSet is applied to a ValueSet, do not convert it into a ValueSet concept or add it to the ValueSet's rules. Log an error containing `ConceptRule` followed by `ValueSet`, and include `File: RuleSets.fsh`, `Line: 8`, `Applied in File: VS.fsh`, and `Line: 7` in the diagnostic.
- When a system-bearing `ConceptRule` from a RuleSet is applied to a CodeSystem, log the error `Do not include the system when listing concepts for a code system.` Include `File: RuleSets.fsh`, `Line: 7`, `Applied in File: CodeSystems.fsh`, and `Line: 3` in the diagnostic.
- Importing a RuleSet that contains a system-bearing `ConceptRule` with no definition and no hierarchy must not log an error.
