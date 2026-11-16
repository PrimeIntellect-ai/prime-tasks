[BUG] Type inference with dot operator assumes `Num` output for `TableRow` lhs
## Current Behaviour

For a table row `$row.column`, the expected output is a `Num`. This should be made more flexible to use type inference.

## Expected Behaviour

## Reproduction Steps
1.

### Additional information

### Additional contract requirements

- The help output for `.` must be exactly:
```text
Help: `.`
--> shell:0
 | extract a value out of a structure using an infix operator
 |
 | Usage:
 |  => . => $foo.bar
 |
 | Examples:
 |  get a value out of a structure using infix operator
 |  => $foo.bar
 |
 |  get the value of a column entry in a TableRow
 |  => $table-row.col-name
 |
 |  explicitly constrain output type of a column
 |  => $table-row.col-name:Str
```
- The following evaluation diagnostics must match exactly:

For `fold 1 + $row.'Heading 3'`:
```text
Evaluation Error: table entry for [row:1,col:'Heading 3'] did not have expected type
expected `Number`, found `String`
--> shell:15
 | fold 1 + $row.'Heading 3'
 |                ^^^^^^^^^
--> help: column entries must have a matching type
```

For `fold 'foo' + $row.first`:
```text
Evaluation Error: table entry for [row:1,col:'first'] did not have expected type
expected `String`, found `Number`
--> shell:18
 | fold 'foo' + $row.first
 |                   ^^^^^
--> help: column entries must have a matching type
```

For `nth 1 Tuple #i.snd:Str #i.snd:Num`:
```text
Evaluation Error: table entry for [row:2,col:'snd'] did not have expected type
expected `String`, found `Number`
--> shell:15
 | nth 1 Tuple #i.snd:Str #i.snd:Num
 |                ^^^
--> help: column entries must have a matching type
```
