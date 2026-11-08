Mangled enum members can be used unexpectedly
Checking the following code is success, but it causes emitter panic.
This is because `EnumA_X` is added to symbol table to detect conflict between mangled names and user defined identifiers.
This case should be reported as error.

```systemverilog
enum EnumA {
    X,
}

let a: logic = EnumA_X;
```

### Additional contract requirements

- The error must be an `AnalyzerError::UndefinedIdentifier` diagnostic.
