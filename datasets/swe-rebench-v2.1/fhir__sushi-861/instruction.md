Improve instance support for elements with multiple profiles
If an element specifies multiple profiles, SUSHI seems to not allow you to assign any values to subpaths of that element.  Instead, SUSHI should just use the base type and emit a warning.

See: https://chat.fhir.org/#narrow/stream/215610-shorthand/topic/sushi.3A.20problem.20with.20external.20profiles.20containing.20profiles

### Additional contract requirements

- For the tested element, the warning must include: `Multiple profiles present on element Patient.generalPractitioner.identifier. Base element type will be used instead of any profiles.`
