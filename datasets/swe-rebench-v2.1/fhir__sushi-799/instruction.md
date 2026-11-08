SUSHI is too strict when constraining profiled types
This is easiest to see via an example. If we have the following FSH:
```
Profile: MyDoc
Parent: ch-core-document
* entry[Composition].resource only MyComp

Profile: MyComp
Parent: http://fhir.ch/ig/ch-core/StructureDefinition/ch-core-composition
```
where the `Composition` slice is defined as:
```
   {
        "id" : "Bundle.entry:Composition.resource",
        "path" : "Bundle.entry.resource",
        "min" : 1,
        "type" : [
          {
            "code" : "Resource",
            "profile" : [
              "http://fhir.ch/ig/ch-core/StructureDefinition/ch-core-composition"
            ]
          }
        ]
      }
```
Then SUSHI does not allow the constraint on the `MyDoc` profile, giving the error:
```
The type "MyComp" does not match any of the allowed types: http://fhir.ch/ig/ch-core/StructureDefinition/ch-core-composition
```

This type constraint really should be allowed, because the `MyComp` profile is a sub-type of Resource, and it conforms to the desired profile. We are too strict in our type checking, since we require that `MyComp` is exactly the same type as the `type.code` (So in this case, changing that from `Resource` to `Composition` works), when we should probably just require that `MyComp` is a sub-type of the `type.code`.

### Additional contract requirements

- When a `Foo` profile is constrained against a profiled `Resource` whose compatible child type is `Observation`, the resulting type must be `Observation` with profile `http://hl7.org/fhir/us/minimal/StructureDefinition/Foo`.
