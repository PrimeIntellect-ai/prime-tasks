Make Decimal a java.util.Number

### Additional contract requirements

- `org.ta4j.core.Decimal` must be assignable to `java.lang.Number` (i.e. it must extend `java.lang.Number`), so that a `Decimal` instance can be used anywhere a `java.lang.Number` is expected.
- `Decimal.doubleValue()` must return the represented numeric value as a `double`; for `Decimal.NaN`, it must return `Double.NaN`.

- As a concrete `Number`, `Decimal` must provide `shortValue()`, `intValue()`, `longValue()`, and `floatValue()` conversions for ordinary finite values. Integral conversions truncate any fractional part, and the floating-point conversion represents the decimal value as a `float`.
