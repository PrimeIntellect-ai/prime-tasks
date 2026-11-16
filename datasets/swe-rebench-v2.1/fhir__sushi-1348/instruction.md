Context unnecessarily uses [url]#[elementid] form for resources in the base specification
An extension defined with:
```
Context: Resource
```
results in:
```json
"context": [
  {
    "expression": "http://hl7.org/fhir/StructureDefinition/Resource#Resource",
    "type": "element"
  }
]
```
[FSH Online](https://fshschool.org/FSHOnline/#/share/3suM7Ro)

The [FHIR spec](https://hl7.org/fhir/R5/defining-extensions.html#context) says:
> Element Ids are unique within the base specification, and within a structure definition. The full path for the element is [url]#[elementid]. If there is no #, the Element id is one defined in the base specification

Since `Resource` is in the base specification, SUSHI should output the expression as `Resource`, not `http://hl7.org/fhir/StructureDefinition/Resource#Resource`.
