`fully_qualified_strict_types` must fix attributes
## Feature request

Expected fixing behaviour:
```diff
-#[\Attr]
+#[Attr]
 class Cl {}
```
Support typed properties in `fully_qualified_strict_types`
Currently `fully_qualified_strict_types` can handle multiple scenarios, but does not cover class' properties. We need this fixer to make changes like this:

```diff
 use Foo\Bar;

 class SomeClass
 {
-    private \Foo\Bar $baz;
+    private Bar $baz;
 }
```
