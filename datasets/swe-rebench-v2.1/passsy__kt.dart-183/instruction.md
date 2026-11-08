Add sumOf()
https://kotlinlang.org/api/latest/jvm/stdlib/kotlin.collections/sum-of.html

### Additional contract requirements

- Add a public method `sumOf` callable on any `KtCollection<T>`, available from `package:kt_dart/collection.dart`, with the signature `R sumOf<R extends num>(R Function(T) selector)`.
- `sumOf` returns the sum of the values produced by applying `selector` to every element of the collection, as type `R`.
- If any selected value is a double, the result is a double; otherwise it is an int. For an empty collection there are no selected double values, so the result is integer zero when `R` permits an integer result (for example, when `R` is `num`), even if the selector's declared return type is double. When `R` is explicitly `double`, the empty result is double so the method can return type `R`.
