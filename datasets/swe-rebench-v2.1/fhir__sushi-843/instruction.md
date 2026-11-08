Filter operator "in" can have a code value
As described here:
https://www.hl7.org/fhir/snomedct.html#4.3.1.0.8.2
the filter operator can take a concept as a value, not just a string.

https://github.com/FHIR/sushi/blob/d785865cf9d84e89316b0abec9ff2c9671fd5871/src/import/FSHImporter.ts#L1853

### Additional contract requirements

The `=`, `in`, and `not-in` filter operators accept a code value (a FSH code such as `#code` or `SYSTEM#code`) in addition to a string value. When such a filter uses a code value, the parsed filter's `value` is the corresponding `FshCode`.

String values remain accepted for these operators for backwards compatibility, but are deprecated: when a string value is used with `=`, `in`, or `not-in`, the importer logs a warning whose message contains:

`The match value of filter operator "<operator>" must be a code.`

where `<operator>` is the operator used (`=`, `in`, or `not-in`).

When a value that is neither a string nor a code is used with `=`, `in`, or `not-in`, the importer logs an error whose message contains:

`Not applying value set filter: operator "<operator>" requires a code value.`
