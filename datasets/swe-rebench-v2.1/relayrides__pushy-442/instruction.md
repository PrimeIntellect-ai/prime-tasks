NPE in ApnsPayloadBuilder.setLocalizedAlertMessage
Javadoc for ApnsPayloadBuilder.setLocalizedAlertMessage says:

> @param alertArguments arguments to populate placeholders in the localized alert string; may be {@code null}

But method will fail with NPE if null is passed as alertArgument in this row
[HIDDEN]

Similar NPE will happen in other methods receiving vararg argument

### Additional contract requirements

- Passing a null varargs array to `setLocalizedAlertMessage`, `setLocalizedAlertTitle`, or `setLocalizedAlertSubtitle` must not throw a `NullPointerException`; null or empty argument arrays are treated as no localization arguments.
