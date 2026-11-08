SUSHI converting Reference to CodeableReference in R4B Snapshot1 extensions
If you have an R4B Snapshot1 project (e.g., `fhirVersion: 4.3.0-snapshot1`) and add this definition:
```
Extension: MyExtension
* value[x] only Reference(Resource)
```
SUSHI will (incorrectly) create a differential with this element:
```json
{
  "id": "Extension.value[x]",
  "path": "Extension.value[x]",
  "type": [
   {
      "code": "CodeableReference",
      "targetProfile": [
        "http://hl7.org/fhir/StructureDefinition/Resource"
      ]
    }
  ]
}
```

If you first restrict to just `Reference` and _then_ to `Reference(Resource)`, it works correctly though.

`¯\_(ツ)_/¯`

See: https://chat.fhir.org/#narrow/stream/215610-shorthand/topic/References.20for.204B.20Snapshot.20.231/near/274743533

### Additional contract requirements

- The public method `ElementDefinition.constrainType(onlyRule: OnlyRule, fisher: Fisher)` (in `src/fhirtypes/ElementDefinition.ts`) constrains the element's `type` to the types specified by the rule. Whenever an element allows both `Reference` and `CodeableReference` and the rule targets a reference, it must prefer a matching `Reference` entry and use `CodeableReference` only when no matching `Reference` entry is found.
