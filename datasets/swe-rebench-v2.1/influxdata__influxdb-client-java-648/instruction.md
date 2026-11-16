The empty string is converted to null
Hi there,
When I query the empty string, I find that the value I get is null, So I debug the source code to find the empty string is converted to null.
why it is designed this way?
Below is the source code section.
```
    @Nullable
    private Object toValue(@Nullable final String strValue, final @Nonnull FluxColumn column) {

        Arguments.checkNotNull(column, "column");

        [HIDDEN]

        String dataType = column.getDataType();
        switch (dataType) {
            case "boolean":
                return Boolean.valueOf(strValue);
            case "unsignedLong":
                return Long.parseUnsignedLong(strValue);
            case "long":
                return Long.parseLong(strValue);
            case "double":
                switch (strValue) {
                    case "+Inf":
                        return Double.POSITIVE_INFINITY;
                    case "-Inf":
                        return Double.NEGATIVE_INFINITY;
                    default:
                        return Double.parseDouble(strValue);
                }
            case "base64Binary":
                return Base64.getDecoder().decode(strValue);
            case "dateTime:RFC3339":
            case "dateTime:RFC3339Nano":
                return Instant.parse(strValue);
            case "duration":
                return Duration.ofNanos(Long.parseUnsignedLong(strValue));
            default:
            case "string":
                return strValue;
        }
    }
```

### Additional contract requirements

- For a string column, preserve an empty CSV field as an empty string when the column has no default or its default is empty. This applies to both quoted empty fields (`""`) and unquoted empty fields; they must not become null.
- When a field is empty or missing and its column has a non-empty default, use that default value.
