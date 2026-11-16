Allow deprecation of input values (arguments and input fields)
I haven't find anything about it in gql specs. Am I missing something?

```php
private static function printInputObject(InputObjectType $type)
    {
        $fields = array_values($type->getFields());
        return self::printDescription($type) .
            "input {$type->name} {\n" .
                implode("\n", array_map(function($f, $i) {
                    return self::printDescription($f, '  ', !$i) . '  ' . self::printInputValue($f);
                }, $fields, array_keys($fields))) . "\n" .
            "}";
    }
```
doesn't print deprecation reason vs
```php
private static function printObject(ObjectType $type)
    {
        $interfaces = $type->getInterfaces();
        $implementedInterfaces = !empty($interfaces) ?
            ' implements ' . implode(', ', array_map(function($i) {
                return $i->name;
            }, $interfaces)) : '';
        return self::printDescription($type) .
            "type {$type->name}$implementedInterfaces {\n" .
                self::printFields($type) . "\n" .
            "}";
    }

private static function printFields($type)
    {
        $fields = array_values($type->getFields());
        return implode("\n", array_map(function($f, $i) {
                return self::printDescription($f, '  ', !$i) . '  ' .
                    $f->name . self::printArgs($f->args, '  ') . ': ' .
                    (string) $f->getType() . self::printDeprecated($f);
            }, $fields, array_keys($fields)));
    }
```

Thanks!

### Additional contract requirements

- Arguments and input object fields accept a `deprecationReason` config option and expose it as a public `deprecationReason` property holding the reason string, or null when the value is not deprecated. `Argument::isDeprecated(): bool` and `InputObjectField::isDeprecated(): bool` report whether the value is deprecated.
- The `@deprecated` directive is applicable to `ARGUMENT_DEFINITION` and `INPUT_FIELD_DEFINITION` in addition to `FIELD_DEFINITION` and `ENUM_VALUE`.
- Printing a schema includes the `@deprecated` directive, with its reason when one is given, for deprecated arguments and deprecated input object fields, just as it already does for deprecated fields and enum values.
- GraphQL introspection must expose `__InputValue.isDeprecated: Boolean!` and `__InputValue.deprecationReason: String`. Both `__Field.args` and `__Type.inputFields` accept an `includeDeprecated: Boolean = false` argument; when false or omitted, deprecated input values are excluded from their results, and when true, their results include them. For each input value, `isDeprecated` reports whether it is deprecated and `deprecationReason` returns its reason, or null.
- Validation rejects a required argument or a required input object field that is deprecated, with the messages `Required argument String.test(badArg:) cannot be deprecated.` and `Required input field SomeInputObject.badField cannot be deprecated.` respectively.
