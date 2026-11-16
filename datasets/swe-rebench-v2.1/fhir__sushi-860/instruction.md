Look for R4B in packages2.fhir.org
R4B ballot edition (4.1.0) is currently only in packages2.fhir.org.  We should look there for it like we do for r5.  Also, since it is intended to be temporary, consider looking in packages.fhir.org and then _falling back_ to packages2 if we don't find it.

### Additional contract requirements

- The core FHIR package is chosen from the first supported version in `fhirVersion`: `4.0.x` uses `hl7.fhir.r4.core`, `4.1.x` and `4.3.x` use `hl7.fhir.r4b.core`, and any other supported version uses `hl7.fhir.r5.core`.
- When the chosen core package is a pre-release (`4.1.x`, or any supported version other than `4.0.x` and `4.3.x`), a warning is logged that SUSHI support for pre-release versions of FHIR is experimental.
- R4B and R5 core packages are looked up in `packages.fhir.org` first and, when not found there, fetched from `packages2.fhir.org`.
