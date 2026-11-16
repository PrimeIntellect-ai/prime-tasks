Struct field access fails if expression type is not yet concrete
I was playing around with the new type system and came across this issue:
```
>>> struct F { a: Current, b: Current }
>>> head([F { a: 1A, b: 2A }]).b
error: while type checking
  ┌─ <input:24>:1:28
  │
1 │ head([F { a: 1A, b: 2A }]).b
  │ -------------------------- ^ Can not access field 'b' of non struct type 'T185'
  │ │
  │ T185
```

[HIDDEN]

### Additional contract requirements

- Field access on a valid struct-valued expression must succeed even when the receiver's type has not yet become concrete during type checking.
