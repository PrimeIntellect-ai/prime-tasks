Extension property accessor DRI missing receiver with K2
**Describe the bug**
When switching to K2 dokka (from `org.jetbrains.dokka:analysis-kotlin-descriptors` to `org.jetbrains.dokka:analysis-kotlin-symbols`), the DRIs for extension property accessors have changed to no longer include the receiver type.

**To Reproduce**
Sample property:
```
var String.foo: Int
    get() = 0
    set(value) = Unit
```

From the `DProperty` for `foo`, `getter.dri.callable` used to be `Callable(name=getFoo, receiver=kotlin.String, params=[])` when using K1. With K2 it is now `Callable(name=getFoo, receiver=null, params=[])`, skipping the receiver. The behavior for the setter is similar.

The receiver type is still present on the `DFunction`s themselves (`getter.receiver` is not null), it is just missing from the DRI.

**Dokka configuration**
Dokka version 2.0.20-dev-388
Kotlin version 2.1.10
