Always fallback to packages2.fhir.org when a package doesn't exist at packages.fhir.org
SUSHI currently only checks packages2.fhir.org for FHIR R4B and FHIR R5 builds.  Instead, we should check packages2.fhir.org _whenever_ a package isn't found in packages.fhir.org.

See: https://chat.fhir.org/#narrow/stream/179252-IG-creation/topic/fhir.2Edicom/near/262334652

### Additional contract requirements

- If loading `fhir.dicom#2021.4.20210910` fails locally and from the registries, the error message must be `The package fhir.dicom#2021.4.20210910 could not be loaded locally or from the FHIR package registry`.
