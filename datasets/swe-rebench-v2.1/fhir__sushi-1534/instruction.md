SUSHI does not auto-load extensions / terminology packages for FHIR R6
SUSHI does not automatically load the extensions package or terminology package for projects that specify their fhirVersion as 6.0.0-ballot2. I think this is because our auto-package loading mechanism looks up those packages based on FHIR version, and SUSHI is missing a mapping for version 6.

We should update that code to account for R6 and/or to fall back to the latest known FHIR-specific versions (E.g., currently the R5 versions) when we don't  have a mapping for the requested FHIR version.

Currently, authors can work around this by adding the latest R5 versions to their dependencies:
```yaml
dependencies:
  hl7.fhir.uv.extensions.r5: latest
  hl7.terminology.r5: latest
```
