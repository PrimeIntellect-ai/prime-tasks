Conflicting imports are sometimes generated in Anvil 2.4.6+
Use case: When there is a simple name conflict between two imports and one of them is an inner class, the resulting alias that gets created for the inner class can conflict with other imports. So far the following snippet is the smallest reproducible use-case that mimics the sort of setup we noticed this issue in for assisted factories.

```
      package com.squareup.test

      import javax.inject.Inject

      class InjectClass @Inject constructor() {
        interface Factory {
          fun doSomething()
        }
      }

      class InjectClassFactory @Inject constructor(val factory: InjectClass.Factory)
```

We started seeing this issue in Anvil 2.4.6 after upgrading to KotlinPoet 1.13.0. I filed https://github.com/square/kotlinpoet/issues/1648 but it turns out this is a long-standing bug in Anvil that only coincidentally worked with previous versions of KotlinPoet. The bug is that when we convert `FqName`s to `ClassName`s, there are some situations like the one above where we incorrectly identify which parts of a fully qualified name are the package and which are simple names (e.g. in the case of a nested class). In the above code, this would result in us creating a `ClassName(package = "com.squareup.test.InjectClass", simpleNames = listOf("Factory"))` when it should be `ClassName(package = "com.squareup.test", simpleNames = listOf("InjectClass", "Factory")`
