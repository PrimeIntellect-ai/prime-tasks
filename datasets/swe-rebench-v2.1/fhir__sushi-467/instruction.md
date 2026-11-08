Remove warning about inline extensions
When someone uses an inline extension which has the same name/id as an externally defined extension, SUSHI emits a warning similar to:
```
 Extension with slice name 'period' will be treated as an inline extension, even though the name can be resolved to the external extension: http://hl7.org/fhir/StructureDefinition/organization-period. Starting with SUSHI 0.10.0, extension slices using standalone extensions should explicitly declare a slice name and type. If this extension slice should refer to http://hl7.org/fhir/StructureDefinition/organization-period, recommended practice is to define an alias:
  Alias: PeriodExtension = http://hl7.org/fhir/StructureDefinition/organization-period
then use it in the contains rule:
  extension contains PeriodExtension named period 0..1
If this extension is intended to be inlined, and not refer to http://hl7.org/fhir/StructureDefinition/organization-period, then no action is necessary. This warning will be removed in a future version of SUSHI after authors have had time to transition.
```
That warning was added in SUSHI 0.10.0 on March 7th, so it has been over 2 months. I'd say it may be time we lose the warning.
