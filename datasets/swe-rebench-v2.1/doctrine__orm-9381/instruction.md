ReflectionEnumProperty throws error on AttributeReader::getPropertyAnnotations()
### Bug Report

|    Q        |   A
|------------ | ------
| BC Break    | no
| Version     | 2.11.0

#### Summary

An Error "Internal error: Failed to retrieve the reflection object" is thrown when calling `AttributeReader::getPropertyAnotations` [HIDDEN].
In my specific case I 'm using custom annotations I have to read for custom behaviour. When trying to retrieve the custom annotations the error occurs.

#### Current behavior
When trying to fetch all or a specific annotation of an entity property, the call fails with an error "Internal error: Failed to retrieve the reflection object".

#### How to reproduce

```
enum Suit: string {
    case Hearts = 'H';
    case Diamonds = 'D';
    case Clubs = 'C';
    case Spades = 'S';
}

#[Entity]
class Card
{
    /** ... */

    #[Column(type: 'string', enumType: Suit::class)]
    #[AnyCustomAnnotation(param: 'bla')]
    public $suit;
}

/** ... */

// @var \Doctrine\ORM\EntityManager
$metadata = $objectManager->getClassMetadata(Card::class);

foreach ($metadata->fieldMappings as $field => $mapping) {
    $property = $metadata->getReflectionProperty($field);
    // @var Doctrine\ORM\Mapping\Driver\AttributeReader
    $isCustom = $reader->getPropertyAnnotation($property, AnyCustomAnnotation::class);
    /** ... */
}

```

#### Expected behavior

The expected behaviour should return the property attributes like `ReflectionProperty::getAttributes()` is supposed to. [HIDDEN]

### Additional contract requirements

- For an enum-mapped entity property, `ReflectionProperty::getAttributes()` should return the attributes declared on that property. When an attribute name is specified, it should return the matching attributes.
- `AttributeReader::getPropertyAnnotations()` should retrieve all annotations from an enum-mapped entity property, and `AttributeReader::getPropertyAnnotation()` should retrieve a requested annotation, including a custom annotation.
