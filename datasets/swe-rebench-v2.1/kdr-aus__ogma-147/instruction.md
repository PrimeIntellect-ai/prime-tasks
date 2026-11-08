[BUG] `last` is getting inferred as `Str` input
## Current Behaviour

`ls | grp name | fold 0 { \$row | get value | last get:Num size }` results in an error suggesting that `last` has too many arguments. This is incorrect, the type inference has incorrectly assumed the input of `last` is `Str` and is using that case to work the inference.

## Expected Behaviour

The error message should be more about the types, the guess of `Str` is overly optimistic, instead it should suggest `Str` or `Table`.

## Reproduction Steps
1.

### Additional information

### Additional contract requirements

When a type-inference error is reported for `last`, the error message must mention the types `Table` and `String` (the type name for `Str`), rather than assuming `Str` alone.
