Instrumentation APK should not be required if roboscript is specified.
We should require that either the instrumentation APK is specified or the robo script. Right now fladle requires that the instrumentation APK is always set meaning that roboscript cannot be used.

Thanks @digitalbuddha for reporting.

### Additional contract requirements

- If both or neither are specified, throw an `IllegalStateException` with this exact message, substituting the configured values (or `null` when absent):

```
Either instrumentationApk file or roboScript file must be specified but not both.
instrumentationApk=<instrumentationApk value>
roboScript=<roboScript value>
```
