SUSHI handles value[x] assignments incorrectly in Instance
If a profile constrains `value[x]` to a single type, and an author assigns `value[x]` in an instance of that profile, then SUSHI incorrectly serialized the property as `value[x]` rather than using its type-specific name.  For example:
```
Profile: BooleanObservation
Parent: Observation
* value[x] only boolean

Instance: MyObservation
InstanceOf: BooleanObservation
* status = #final
* code = http://example#somecode
* value[x] = true
```
produces the following instance:
```json
{
  "resourceType": "Observation",
  "id": "MyObservation",
  "meta": {
    "profile": [
      "http://example.org/StructureDefinition/BooleanObservation"
    ]
  },
  "status": "final",
  "code": {
    "coding": [
      {
        "code": "somecode",
        "system": "http://example"
      }
    ]
  },
  "value[x]": true
}
```
Note that the last property should be `"valueBoolean": true`.

Either SUSHI needs to disallow assignment to `value[x]` in Instances or it needs to handle it correctly. I'd prefer to handle it correctly, but if that proves to be complex, it may be reasonable to disallow it.

### Additional contract requirements

SUSHI must handle assignment to a generic choice element (such as `value[x]`) in an Instance by
rewriting the path to the type-specific element name whenever the choice element is constrained to a
single type. Disallowing the assignment is not an acceptable resolution: the value must be assigned
and serialized under the type-specific property name. For the Boolean example above, the instance
must contain `"valueBoolean": true` and must not contain a `"value[x]"` property.

When SUSHI rewrites such a path, it must emit a warning whose message is exactly
`When assigning values on instances, use the choice element's type. Rule path changed from '<original path>' to '<rewritten path>'.`
where `<original path>` and `<rewritten path>` are the rule path before and after rewriting. Assigning
`value[x]` when `value[x]` is constrained to `string` therefore emits exactly
`When assigning values on instances, use the choice element's type. Rule path changed from 'value[x]' to 'valueString'.`

When a choice element in the path has more than one possible type and therefore cannot be rewritten
to a single type-specific name, SUSHI must not assign the value, must leave the path unchanged, must
not emit a warning, and must emit an error whose message is exactly
`Unable to assign value at <path>: choice elements on an instance must use a specific type`
where `<path>` is the rule path. Assigning `value[x].extension.url` when `value[x]` is constrained to
`string or boolean` therefore emits exactly
`Unable to assign value at value[x].extension.url: choice elements on an instance must use a specific type`.
