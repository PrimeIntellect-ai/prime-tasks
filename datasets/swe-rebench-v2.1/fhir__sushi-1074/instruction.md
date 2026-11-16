Setting extensions by URL/id does not work correctly for CodeSystems and ValueSets
If you set an extension on a profile or extension, it works as expected.  E.g.,
```
Profile: MyPatient
Parent: Patient
* ^extension[structuredefinition-fmm].valueInteger = 1
```
results in
```json5
"extension": [
  // Some extensions omitted for brevity
  {
    "url": "http://hl7.org/fhir/StructureDefinition/structuredefinition-fmm",
    "valueInteger": 1
  }
]
```

But if you do the same for a CodeSystem or ValueSet, it creates an incorrect extension.  E.g.,
```
CodeSystem: MyCodeSystem
* ^extension[structuredefinition-fmm].valueInteger = 1
* #foo "Foo" "Foo"
```
results in
```json
"extension": [
  {
    "_sliceName": "structuredefinition-fmm",
    "valueInteger": {
      "assignedValue": 1,
      "_primitive": true
    }
  }
]
```

The following FSH Online snippet shows where this works (Profile, Extension, Instance) and where it doesn't (CodeSystem, ValueSet): https://fshschool.org/FSHOnline/#/share/3jZbrHQ
