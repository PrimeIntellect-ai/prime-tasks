Polymorphic generation creates empty JsonSubtypes
If your schema casing isn't consistent with the class name casing, the JsonSubtypes value of polymorphic discriminator objects is empty.

e.g., given this (where only the case of `polymorphicEnumDiscriminator` is modified from the example in the project:

```yaml
openapi: 3.0.0
paths: {}
info:
  title: ""
  version: ""
components:
  schemas:
    Wrapper:
      type: object
      properties:
        polymorph:
          $ref: '#/components/schemas/polymorphicEnumDiscriminator'
    polymorphicEnumDiscriminator:
      type: object
      discriminator:
        propertyName: some_enum
        mapping:
          obj_one_only: '#/components/schemas/ConcreteImplOne'
          obj_two_first: '#/components/schemas/ConcreteImplTwo'
          obj_two_second: '#/components/schemas/ConcreteImplTwo'
          obj_three: '#/components/schemas/ConcreteImplThree'
      properties:
        some_enum:
          $ref: '#/components/schemas/EnumDiscriminator'

    ConcreteImplOne:
      allOf:
        - $ref: '#/components/schemas/polymorphicEnumDiscriminator'
        - type: object
          properties:
            some_prop:
              type: string

    ConcreteImplTwo:
      allOf:
        - $ref: '#/components/schemas/polymorphicEnumDiscriminator'
        - type: object
          properties:
            some_prop:
              type: string

    ConcreteImplThree:
      allOf:
        - $ref: '#/components/schemas/polymorphicEnumDiscriminator'

    EnumDiscriminator:
      type: string
      enum:
        - obj_one_only
        - obj_two_first
        - obj_two_second
        - obj_three
```

you get:

```kotlin
@JsonTypeInfo(
  use = JsonTypeInfo.Id.NAME,
  include = JsonTypeInfo.As.EXISTING_PROPERTY,
  property = "some_enum",
  visible = true
)
@JsonSubTypes()
sealed class PolymorphicEnumDiscriminator() {
  abstract val someEnum: EnumDiscriminator
}
```

It doesn't seem like the case of anything else matters, just the discriminator object.
