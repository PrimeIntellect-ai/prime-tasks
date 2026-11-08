Way to skip Exception/Error when field does not have a mapping or alias
Hello there,

While using the `Entity.putBatch` followed by `table.batchWrite()` I incurred in the following error:
`Error: Field 'newField' does not have a mapping or alias`

The entity I want to persist comes from an external API, so it can happen that some new fields are added without notice, and that's exactly what happened in this case.
Is there a way to instruct dynamodb-toolbox to just "skip" persistence of unknown fields, instead
of rising this error?

Or is there a better way to approach this kind of problem?

@jeremydaly Thank you very much for the help!

### Additional contract requirements

`Entity.putBatch` accepts the `strictSchemaCheck` option. When it is `false`, unmapped fields in the supplied item are omitted from the generated batch-write item. When the option is omitted or `true`, unmapped fields continue to produce the existing error.
