[refactor] have a semi-structured tracing output
Example

```
sg: summary|file: scannedCount=199
sg: entity|file|src/cli/scan.rs: skippedCount=47
sg: entity|rule|my-rule-id: finalSeverity=off
sg: entity|rule|my-rule-id: skipReason=ruleFilter
sg: entity|rule|my-rule-id: skipReason=severityOff
sg: detail|file*rule|src/cli/scan.rs,my-ast-grep-rule: hitResult=hitByInclude
sg: detail|file*rule|src/cli/scan.rs,my-ast-grep-rule: hitResult=hitByExclude
sg: detail|file*rule|src/cli/scan.rs,my-ast-grep-rule: hitResult=normalHit
```

[EBNF](https://en.wikipedia.org/wiki/Extended_Backus%E2%80%93Naur_form) notation,

```ebnf
OUTPUT := "sg: ", GRANULARITY,  "|", ENTITY_TYPE, ENTITY_IDENTIFIER_LIST , ": ", KEY_VAL_PAIR;
GRANULARITY = "summary" | "entity" | "detail";
ENTITY_TYPE = "file" | "rule" | "file*rule";
ENTITY_IDENTIFER_LIST = "" | ( "|", IDENTIFIER { IDENTIFIERS } );
IDENTIFIERS = ",", IDENTIFIER;
KEY_VAL_PAIR = KEY, "=", VAL;
```

Informal Notation

```
sg: <GRANULARITY>|<ENTITY_TYPE>|<ENTITY_IDENTIFIERS_SEPARATED_BY_COMMA>: KEY=VAL
```

### Additional contract requirements

The semi-structured tracing lines use these exact key names and formats:

- Summary file line (emitted for both run and scan tracing):
  `sg: summary|file: scannedFileCount=<n>,skippedFileCount=<m>`
- Summary rule line (emitted additionally when tracing a scan that has rules):
  `sg: summary|rule: effectiveRuleCount=<n>,skippedRuleCount=<m>`
- Entity file line:
  `sg: entity|file|<path>: language=<lang>` for a run, and
  `sg: entity|file|<path>: language=<lang>,appliedRuleCount=<n>` for a scan.

The granularity token in each line is the lowercase `Debug` form of the level:
`nothing`, `summary`, or `entity`.
