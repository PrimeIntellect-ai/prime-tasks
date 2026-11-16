InputNumber: `Number` identified as non-decimal
### Describe the bug

a PRO reported an issue related to InputNumberRenderer.isIntegral method. Will we add decimal type checks for Number type?

```java
// InputNumberRenderer.java
private boolean isIntegral(FacesContext context, InputNumber inputNumber, Object value) {
        if (value != null) {
            return value instanceof Long
                    || value instanceof Integer
                    || value instanceof Short
                    || value instanceof BigInteger
                    || value instanceof Byte;
        }

        Class<?> type = getTypeFromValueExpression(context, inputNumber);
        if (type == null) {
            return false;
        }

        [HIDDEN]
    }
```

As you know, java.lang.Number is a superclass of Integer, Long, Short, [...].
Since the upgrade from 11.0.7 to 13.0.8 we face the issue that p:inputNumber defaults to 0 decimalPlaces when using a java.lang.Number (initial value null) as value.
This seems to happen because the check for integral, with a null value, [HIDDEN]
Thus, it returns true, even though java.lang.Number can have decimalPlaces.

### Reproducer

```java
private Number number;
```

```xml
<p:inputNumber value="#{testView.number}" />
```

### Expected behavior

_No response_

### PrimeFaces edition

Community

### PrimeFaces version

13.0.8

### Theme

_No response_

### JSF implementation

Mojarra

### JSF version

2.3

### Java version

11

### Browser(s)

_No response_

### Additional contract requirements

- Add a protected method `boolean isIntegral(FacesContext context, InputNumber inputNumber, Object value)` in `org.primefaces.component.inputnumber.InputNumberRenderer`.
- When the value is non-null, the method returns `true` for a `Byte`, `Short`, `Integer`, `Long`, or `BigInteger` value, and `false` for any other value (including decimal types such as `BigDecimal`).
- When the value is `null`, the method returns `true` only when the component's bound value type is `Byte`, `Short`, `Integer`, `Long`, or `BigInteger`.
- When the value is `null`, the method returns `false` for decimal types such as `BigDecimal`, for `java.lang.Number`, and when the bound value type cannot be determined.
