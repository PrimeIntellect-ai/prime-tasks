Constraining Canonicals does not support canonicals w/ versions
You can now do:
```
* action.definition[x] only Canonical(Questionnaire)
```
and
```
* action.definition[x] only Canonical(http://hl7.org/fhir/StructureDefinition/Questionnaire)
```
BUT you cannot do:
```
// broken
* action.definition[x] only Canonical(Questionnaire|4.0.1)
```
or
```
// broken
* action.definition[x] only Canonical(http://hl7.org/fhir/StructureDefinition/Questionnaire|4.0.1)
```

We need to support this too.

### Additional contract requirements

- The version supplied in a versioned canonical type constraint is appended to the target profile URL recorded on the element's type. For example, `only Canonical(Questionnaire|4.0.1)` produces a `canonical` type whose target profile is `http://hl7.org/fhir/StructureDefinition/Questionnaire|4.0.1`, and `only Canonical(http://hl7.org/fhir/StructureDefinition/Questionnaire|4.0.1)` produces that same target profile.
- When a value is assigned to an element constrained with a versioned canonical, the version is not checked: any instance of the constrained target type is accepted regardless of the version of the profile it is an instance of.
