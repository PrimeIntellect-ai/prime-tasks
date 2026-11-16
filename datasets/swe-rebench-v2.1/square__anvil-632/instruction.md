AnnotationArgumentReference.Psi does not parse string templates correctly
The string template parsing [Here](https://github.com/square/anvil/blob/855e55baeb8afdd81b22277f8477e86490ec5e2d/compiler-utils/src/main/java/com/squareup/anvil/compiler/internal/reference/AnnotationArgumentReference.kt#L267) does not currently grab the entire string. When given a blob like

```kotlin
const val SOME_STR: String = "World!"

@AnnotatedWith(value = "Hello, $SOME_STR")
object SomeObj {}
```

`annotationArgRef.value<Any>()` returns the string `"Hello, "`. Seeing as the compiler enforces that all template entries are constantly resolvable the entire value should be resolvable, which would bring this in line with the other available expression types.
