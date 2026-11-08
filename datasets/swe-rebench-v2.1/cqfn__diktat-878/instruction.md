Not all types of nodes for annotation Suppress are considered
When we check whether the node has a parent annotated with `@Suppress`,
we finding the type `MODIFIER_LIST`.

However, in this example, the actual type of node is [HIDDEN]


```kotlin
fun foo () {
     if (true) {
         @Suppress("COLLAPSE_IF_STATEMENTS")
         if (true) {
             if (true) {
                 doSomething()
             }
         }
     }
}
```

Thus, the warning for the last `if` will be still remain. And only for second `if` warning will be suppressed.

### Additional contract requirements

- When `@Suppress` is applied to an annotated expression, matching warnings within that expression, including on nested expressions, must be suppressed.
