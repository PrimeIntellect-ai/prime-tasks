Include property name that failed to serialize in error messages
**I get this error:**

`SEVERE [org.eclipse.yasson.internal.Marshaller] double value cannot be Infinite or NaN`

Please include the **"property name"** in this error message which makes the trouble. It's a mess to search for that property manually.

### Additional contract requirements

- For a failure while serializing an object property, the exception message chain must include `Unable to serialize property '<property name>'` and the serialized object's class name.
