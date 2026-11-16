NPE on Validator#handleImplementationSelected, line 740, v1.10.2
It works with 1.10.1, but fails with 1.10.2. Test case is attached.

[validation-npe-impl-schema.zip](https://github.com/xlate/staedi/files/5183575/validation-npe-impl-schema.zip)

### Additional contract requirements

Validating the reported input against the reported implementation schema must complete without throwing an exception, in particular without a `NullPointerException`, and must not report any segment, element-occurrence, or element-data validation error events.
