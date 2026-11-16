Duplicated discriminator names
If the same field name is used in separate objects for their individual discriminators then generation station is adding all possible classes as JSON deserialization sub classes.
Please see below example:


```
openapi: 3.0.0
components:
  schemas:
    PolymorphicSuperTypeOne:
      x-fabric-resource-definition: true
      type: object
      discriminator:
        propertyName: shared
      required:
        - shared
      properties:
        shared:
          type: string
    PolymorphicTypeOneA:
      allOf:
        - $ref: "#/components/schemas/PolymorphicSuperTypeOne"
        - type: object
          properties:
            whateverA:
              type: string
    PolymorphicTypeOneB:
      allOf:
        - $ref: "#/components/schemas/PolymorphicSuperTypeOne"
        - type: object
          properties:
            whateverB:
              type: integer
              format: int32
    PolymorphicSuperTypeTwo:
      x-fabric-resource-definition: true
      type: object
      discriminator:
        propertyName: shared
      required:
        - shared
      properties:
        shared:
          type: string
    PolymorphicTypeTwoA:
      allOf:
        - $ref: "#/components/schemas/PolymorphicSuperTypeTwo"
        - type: object
          properties:
            whateverC:
              type: string
    PolymorphicTypeTwoB:
      allOf:
        - $ref: "#/components/schemas/PolymorphicSuperTypeTwo"
        - type: object
          properties:
            whateverD:
              type: integer
              format: int32
```


Generates something like:

```
@JsonTypeInfo(
    use = JsonTypeInfo.Id.NAME,
    include = JsonTypeInfo.As.EXISTING_PROPERTY,
    property = "shared",
    visible = true
)
@JsonSubTypes(
    JsonSubTypes.Type(
        value = PolymorphicTypeOneA::class,
        name =
            "PolymorphicTypeOneA"
    ),
    JsonSubTypes.Type(
        value = PolymorphicTypeOneB::class,
        name =
            "PolymorphicTypeOneB"
    ),
    JsonSubTypes.Type(
        value = PolymorphicTypeTwoA::class,
        name =
            "PolymorphicTypeTwoA"
    ),
    JsonSubTypes.Type(
        value = PolymorphicTypeTwoB::class,
        name =
            "PolymorphicTypeTwoB"
    )
)
sealed class PolymorphicSuperTypeOne(
    open val shared: String
)
```
