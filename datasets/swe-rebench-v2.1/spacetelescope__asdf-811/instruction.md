usage of oneOf for schema validation
I am having trouble getting my schemas to validate when using `oneOf` structures. (running asdf=2.6.0, python=3.7)

Consider the following python/asdf example that I expected to work but somehow cannot implement.
```python
#python class for debugging
@dataclass
class OneOfClass:
    data: dict


class OneOfClassType(CustomType):
    name = "debug/oneOf_class"
    version = "1.0.0"
    types = [OneOfClass]

    @classmethod
    def to_tree(cls, node: OneOfClass, ctx):
        return node.data

    @classmethod
    def from_tree(cls, tree, ctx):
        obj = OneOfClass(tree)
        return obj
```
The schema I wanted to implement:
```yaml
%YAML 1.1
---
$schema: "http://stsci.edu/schemas/yaml-schema/draft-01"
id: "http://somewhere.com/schemas/debug/oneOf_class-1.0.0"
tag: "tag:somewhere.com:debug/oneOf_class-1.0.0"

title: |
  oneOf test schema
oneOf:
  - type: object
    properties:
      value:
        type: number
    required: [value]
    additionalProperties: false

  - type: object
    properties:
      value:
        type: string
    required: [value]
    additionalProperties: false
...
```

Now the following will fail:
```python
with asdf.AsdfFile(
    tree={"obj_a": OneOfClass({"value": "a string"})},
    extensions=[CustomExtension()],
) as ff:
    ff.write_to("oneOf.asdf")
```

```python
jsonschema.exceptions.ValidationError: {'value': 'a string'} is valid under each of OrderedDict([('type', 'object'), ('properties', OrderedDict([('value', OrderedDict([('type', 'string')]))])), ('required', ['value']), ('additionalProperties', False)]), OrderedDict([('type', 'object'), ('properties', OrderedDict([('value', OrderedDict([('type', 'number')]))])), ('required', ['value']), ('additionalProperties', False)])
```

If I only keep the string part of the schema as the single `oneOf` entry, it works. (same when trying to store a number, only works when the number part is the only `oneOf` list entry)
```yaml
oneOf:
#  - type: object
#    properties:
#      value:
#        type: number
#    required: [value]
#    additionalProperties: false

  - type: object
    properties:
      value:
        type: string
    required: [value]
    additionalProperties: false
...
```

When changing `oneOf` to `allOf` I get `jsonschema.exceptions.ValidationError: 'a string' is not of type 'number'`
Using `anyOf` in the original example works.

While I can get by using `anyOf` I would prefer `oneOf` for clarity and peace of mind. Any hints are appreciated.

### Additional contract requirements

- A value satisfies a `oneOf` schema only when it matches exactly one alternative; values matching none or more than one alternative are invalid.
- Filling and removing defaults must traverse `allOf` subschemas.
