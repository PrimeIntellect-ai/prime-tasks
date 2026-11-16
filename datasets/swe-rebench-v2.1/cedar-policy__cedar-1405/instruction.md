Carry source info through schema structures
### Category

Internal refactors/changes -- consider "Internal improvement" instead of "Feature request"

### Describe the feature you'd like to request

#174 requests source-location information for errors in JSON schemas.  This issue has a smaller scope -- it asks that we simply carry source-location information inside the schema JSON structures, and propagate it from the human-syntax as the human-syntax is converted to the JSON structures in `to_json_schema.rs`.  This should be sufficient to get source locations in many human-syntax errors, even without providing source locations for errors in JSON syntax (that is still #174).

### Describe alternatives you've considered

This is an optional stepping stone to #174 with reduced scope.

### Additional context

_No response_

### Is this something that you'd be interested in working on?

- [ ] 👋 I may be able to implement this feature request
- [ ] ⚠️ This feature might incur a breaking change

### Additional contract requirements

- When a schema is parsed from the Cedar (human) syntax, the source location carried on each `EntityDecl`, `ActionDecl`, and `TypeDecl` must be propagated to the corresponding structure in the JSON schema representation (the `loc` field on the JSON `EntityType`, `ActionType`, and `CommonType`).
- The propagated location must be a valid span of the original source that identifies the declaration, i.e. its snippet contains the declaration's name.
