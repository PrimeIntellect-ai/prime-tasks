Struct member is not allowed as factor
```systemverilog
let a: logic = struct_variable.struct_member; // error
```

### Additional contract requirements

The statement above reports the pre-fix behavior: a struct member used as a factor is
rejected with an error. The requested change is to allow a struct member to be used as a
factor. After the change, using a struct member as a factor must be accepted without error in both
declaration initializers and assignment right-hand sides. For example, given a struct variable
`a` with a member `a`, both `let d: logic = a.a;` and the assignment `assign d = a.a;` must
analyze without error.
