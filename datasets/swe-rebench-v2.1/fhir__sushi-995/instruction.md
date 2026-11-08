SUSHI does not support FHIR 5.0.0-snapshot1
If you specify the `fhirVersion` as `5.0.0-snapshot1`, SUSHI will complain:
> The sushi-config.yaml must specify a supported version of FHIR. Be sure to add "fhirVersion: 4.0.1" (or 4.x.y, as appropriate) to the sushi-config.yaml file.

https://chat.fhir.org/#narrow/stream/215610-shorthand/topic/R5.20support

### Additional contract requirements

When `fhirVersion` is specified as `5.0.0-snapshot1`, SUSHI must accept it as a supported version and load the FHIR R5 core package (`hl7.fhir.r5.core`) at version `5.0.0-snapshot1`, rather than rejecting it as unsupported.
