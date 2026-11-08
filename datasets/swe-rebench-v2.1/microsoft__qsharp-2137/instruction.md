panic when referencing reexported UDT from another package

When a package references a re-exported UDT from a dependency, a panic occurs:

```
panicked at `compiler/qsc_frontend/src/typeck/convert.rs:123:13:
internal error: entered unreachable code: A path should never resolve to a local or a parameter, as there is syntactic differentiation.
```


This bug occurs if we try to use `TestCaseResult` from `qtest` package today (but you have to work around #1955 first)

https://github.com/microsoft/qsharp/blob/6d83547a003bcde6032398d46eb0d645c8224053/library/qtest/src/Main.qs#L4


**REPRO**

We need two Q# packages for this:


**`dep/qsharp.json`**

```json
{}
```

**`dep/src/Main.qs`**

```qsharp
namespace Foo {
    struct MyType { a: Int }
}

namespace Main {
    export Foo.MyType as MyType; // work around https://github.com/microsoft/qsharp/issues/1955 by using an alias
}
```

**`main/qsharp.json`**

```json
{
  "dependencies": {
    "dep": {
      "path": "../dep"
    }
  }
}
```

**`main/src/Main.qs`**

```qsharp
operation Main() : Unit {
    let x = new dep.MyType { a = 1 };  // this usage triggers the panic
}
```


panicked at `compiler/qsc_frontend/src/typeck/convert.rs:123:13:`
internal error: entered unreachable code: A path should never resolve to a local or a parameter, as there is syntactic differentiation.



Seen in 2a4c33552e94bce95c91d8936dcf45a601e6b2b2
