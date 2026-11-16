RFC: Graphcache warnings for configs
## Summary

Currently a couple of warnings in Graphcache are just dedicated to checking the user's input when "schema awareness" is active. In other words, when we have a schema, we check whether some fields even exist on the schema, and if they don't the user will see a warning: https://github.com/FormidableLabs/urql/blob/ecb58bfdd97ed660a2dd248fd51e44c07b7350b5/exchanges/graphcache/src/ast/schemaPredicates.ts#L62-L113

Such a warning doesn't exist for fields in the config, like `opts.updates.Mutation.oopsTypo`; It'd be great to add those and take this opportunity to also _test_ whether our existing warnings still work correctly!

## Proposed Solution

- Add checks for all `config` fields that relate to the `schema`, if one has been passed
- Add tests for `query` and `write` operations to check whether warnings don't mis-trigger

## Requirements

- When `opts.schema` has been passed, use new schema predicates to warn whether `opts.updates`, `opts.resolvers`, and `opts.optimistic` contain fields that don't exist on the schema
- When `opts.schema` has been passed, use new schema predicates to warn whether `opts.keys` contains typenames that don't exist on the schema
