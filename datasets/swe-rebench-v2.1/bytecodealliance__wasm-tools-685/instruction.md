components: Realloc not required when it should be
This module:

```wasm
(component
  (core module $m
    (memory (export "memory") 1)
    (func (export "roundtrip") (param i32))
  )
  (core instance $m (instantiate $m))

  (type $roundtrip (func
    (param u32) (param u32) (param u32) (param u32) (param u32)
    (param u32) (param u32) (param u32) (param u32) (param u32)
    (param u32) (param u32) (param u32) (param u32) (param u32)
    (param u32) (param u32) (param u32) (param u32) (param u32)
  ))

  (func $roundtrip (type $roundtrip)
    (canon lift (core func $m "roundtrip") (memory $m "memory"))
  )
  (export "roundtrip" (func $roundtrip))
)
```

should require the `realloc` parameter on the `canon lift` to be specified, but currently it validates in wasmparser.
