MULTIPLE_INIT_BLOCKS: fixer can break the code
Diktat 1.0.0-RC2:

```
class A {
    var a: String

    init {
        val b: String = "a"
        a = b
    }
}
```

MULTIPLE_INIT_BLOCKS fixer can break the code:
```
class A {
    var a: String = b

    init {
        val b: String = "a"
    }
}
```

### Additional contract requirements

- When an `init` block assigns properties from local `val` declarations in that block, including assignments such as `a = b` and `c = foo(d)`, linting must not emit a `MULTIPLE_INIT_BLOCKS` warning.
