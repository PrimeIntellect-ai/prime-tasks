Support dataclass inheritance using allOf
The `allOf` keyword can be used to support composition. So from the example given in the swagger docs:

```python
@dataclass
class Pet(JsonSchemaMixin):
    name: str

@dataclass
class Cat(Pet):
    hunting_skill: HuntingSkill
```

would generate the following schema:

```yaml
definitions:
  Pet:
    type: object
    properties:
      name:
        type: string
    required:
    - name
  Cat:
    description: A representation of a cat
    allOf:
    - $ref: '#/definitions/Pet'
    - type: object
      properties:
        hunting_skill:
          type: string
          enum:
...
```

**Note:** I don't plan to support the `discriminator` keyword when generating swagger schemas.
