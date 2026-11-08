Different json key and PHP variable naming
I have a json structure that has a property called `categories[]`. The problem is that this thing cannot be mapped, because it contains special characters in the name, so I cannot declare `$categories[]` as variable name in PHP.

Having a possibility to add manual mapping description would be very useful. I can imagine this being used in many various scenarios where developers do not want the json key and the PHP variable having the exact same name.

### Additional contract requirements

Add a public class `Mapping` in the namespace `JsonMapper\Middleware\Rename` that describes a single rename rule:
- `__construct(string $class, string $from, string $to)` stores the fully-qualified class name the rule applies to, the original JSON property name, and the target PHP property name.
- `getClass(): string` returns the class name the rule applies to.
- `getFrom(): string` returns the original JSON property name.
- `getTo(): string` returns the target PHP property name.

Add a public class `Rename` in the namespace `JsonMapper\Middleware\Rename` that applies rename rules while JSON is mapped onto objects:
- It can be instantiated without arguments.
- `addMapping(string $class, string $from, string $to): void` registers an additional rename rule for the given class.
- `handle(\stdClass $json, ObjectWrapper $object, PropertyMap $propertyMap, JsonMapperInterface $mapper): void` renames, for every registered rule whose class matches the class of the object being mapped, the JSON property named by the rule's source to the rule's destination when that property is present with a non-null value, leaving every other property unchanged.

Source and destination names may contain any characters that are valid JSON object keys, such as `Full-Name` or `FULL-NAME`.
