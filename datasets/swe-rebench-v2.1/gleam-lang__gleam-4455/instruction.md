Unqualify code action readds import
When you have imported a module unqualified but you have it written with the module, the code action will readd the existing import.

Example:
```gleam
import gleam/dict.{type Dict}

pub fn a(d: dict.Dict(Int, Int)) {
  Nil
}
```
becomes
```gleam
import gleam/dict.{type Dict, type Dict}

pub fn a(d: Dict(Int, Int)) {
  Nil
}
```

Gleam: v1.9.1
