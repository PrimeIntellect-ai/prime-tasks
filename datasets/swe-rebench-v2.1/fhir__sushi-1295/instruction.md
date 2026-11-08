SUSHI drops version in versioned "only" rules
Given this FSH:
```
Profile: MyPatient
Parent: Patient
* ^version = "1.0"

Profile: MyComposition
Parent: Composition
* section.entry only Reference(MyPatient|1.0)
```

SUSHI drops the version when it constrains `section.entry`:
```json
      {
        "id": "Composition.section.entry",
        "path": "Composition.section.entry",
        "type": [
          {
            "code": "Reference",
            "targetProfile": [
              "http://example.org/StructureDefinition/MyPatient"
            ]
          }
        ]
      }
```

Since `targetProfile` is a `canonical`, it should retain the `|1.0`.

See: https://chat.fhir.org/#narrow/stream/215610-shorthand/topic/Adding.20version.20to.20Reference
