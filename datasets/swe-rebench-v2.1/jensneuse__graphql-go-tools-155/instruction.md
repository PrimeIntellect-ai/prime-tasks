[Critical] Add validator for string and float input types
Use case query
```
someendpoint(id: String!): Somemodel
```
produces the error
```
 {"error": "internal: validateIfValueSatisfiesInputFieldDefinition: not implemented for value.Kind: ValueKindString"}
```
