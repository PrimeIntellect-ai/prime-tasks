Sliced meta.profile with version number forcing instances to have an extra meta.profile repeat without version number.
If there is a profile slice requirement for meta.profile where the canonical requires a version number, and FSH generated instance of the resource will have 2 meta.profile instances one with and one without the version number. If the latest version of the profile changed with breaking changes, this can cause a validation issue.

Occurs with the CARIN BlueButton IG.

FSHOnline example: https://fshschool.org/FSHOnline/#/share/3eM13Rq
CARIN BB Jira ticket: https://jira.hl7.org/browse/FHIR-32428
CARIN BB Example: https://build.fhir.org/ig/HL7/carin-bb/Organization-Payer1.json.html
