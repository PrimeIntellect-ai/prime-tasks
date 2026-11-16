Add interface IonNumber above IonDecimal, IonFloat, and IonInt
_Imported from ION-95,IONJAVA-137_

### Additional contract requirements

`IonDecimal`, `IonFloat`, and `IonInt` are subtypes of `IonNumber`. `IonNumber.isNumericValue()` reports whether a value is a concrete numeric value: it is false for nulls and for non-finite float values (NaN and positive or negative infinity), and true for finite numeric values. `IonNumber.bigDecimalValue()` returns the numeric value as a `BigDecimal`, or null for a null value. An integer value must also be convertible through this operation. A non-null value that is not representable as a `BigDecimal`, such as a non-finite float, may cause `NumberFormatException`.
