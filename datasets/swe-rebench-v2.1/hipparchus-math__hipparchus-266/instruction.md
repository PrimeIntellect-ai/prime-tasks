Unusable Splines with Field not heriting from interface Comparable
Any call to method `value` of `FieldSplinePolynomialFunction` (after actual interpolation) fails if the `Field` does not extent `Comparable`, as the code tries to see which polynomial to evaluate by comparing inputs to knots.

See discussion on [forum](https://forum.orekit.org/t/error-when-evaluating-field-linear-splines/2545).
