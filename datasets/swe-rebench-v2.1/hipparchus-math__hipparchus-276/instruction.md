Implement Comparable for UnivariateDerivative
In line with #274 and also [discussions on the forum](https://forum.orekit.org/t/error-when-evaluating-field-linear-splines/2545)

### Additional contract requirements

- `UnivariateDerivative` (in package `org.hipparchus.analysis.differentiation`) implements `Comparable`.
- `UnivariateDerivative1` (in package `org.hipparchus.analysis.differentiation`) provides a public method `int compareTo(UnivariateDerivative1 o)` that orders instances first by the real part (`f0`) and, when the real parts are equal, by the first derivative (`f1`).
- `UnivariateDerivative2` (in package `org.hipparchus.analysis.differentiation`) provides a public method `int compareTo(UnivariateDerivative2 o)` that orders instances first by the real part (`f0`), then, when the real parts are equal, by the first derivative (`f1`), and finally, when both are equal, by the second derivative (`f2`).
- For the comparisons above, the result is exactly `-1` when this instance precedes the other value, exactly `1` when it follows, and `0` when all compared components are equal.
