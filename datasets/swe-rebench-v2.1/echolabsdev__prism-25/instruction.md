Support for `object` and `array` types in Tool params.
OpenAI (and others I believe) allow you to us `object` and `array` types for Tool params. They require additional fields to build the param data, for example;

```
'tags' => [
    'type' => 'array',
    'items' => [
        'type' => 'string',
        'description' => 'Tags or categories for the recipe',
    ],
],
```

```
'nutrition' => [
    'type' => 'object',
    'properties' => [
        'calories' => [
            'type' => 'integer',
            'description' => 'Calories per serving',
        ],
        'fat' => [
            'type' => 'number',
            'description' => 'Fat content in grams per serving',
        ],
        'carbs' => [
            'type' => 'number',
            'description' => 'Carbohydrate content in grams per serving',
        ],
        'protein' => [
            'type' => 'number',
            'description' => 'Protein content in grams per serving',
        ],
    ],
],
```

It might be helpful to consider the building of ValueObjects for params in the future, this could make it easier to define the params without a large list of args to the `withParameter` method.

### Additional contract requirements

Add a public interface `EchoLabs\Prism\Contracts\Schema` with methods `name(): string` (the schema's identifier) and `toArray(): array` (a JSON-compatible representation of the schema).

Add the following public schema classes, each implementing `EchoLabs\Prism\Contracts\Schema`:

- `EchoLabs\Prism\Schema\StringSchema::__construct(string $name, string $description)`; `toArray()` yields `['description' => ..., 'type' => 'string']`.
- `EchoLabs\Prism\Schema\NumberSchema::__construct(string $name, string $description)`; `toArray()` yields `['description' => ..., 'type' => 'number']`.
- `EchoLabs\Prism\Schema\BooleanSchema::__construct(string $name, string $description)`; `toArray()` yields `['description' => ..., 'type' => 'boolean']`.
- `EchoLabs\Prism\Schema\EnumSchema::__construct(string $name, string $description, array $options)` where `$options` are scalar enum values; `toArray()` yields `['description' => ..., 'enum' => $options]`.
- `EchoLabs\Prism\Schema\ArraySchema::__construct(string $name, string $description, Schema $item)`; `toArray()` yields `['description' => ..., 'type' => 'array', 'items' => $item->toArray()]`.
- `EchoLabs\Prism\Schema\ObjectSchema::__construct(string $name, string $description, array $properties, array $requiredFields = [], bool $allowAdditionalProperties = false)` where `$properties` is a list of `Schema` objects; `toArray()` yields `['description' => ..., 'type' => 'object', 'properties' => [...], 'required' => $requiredFields, 'additionalProperties' => $allowAdditionalProperties]`, where `properties` maps each property's name to its `toArray()` result.

Update `EchoLabs\Prism\Tool` with the following public methods:

- `withParameter(Schema $parameter, bool $required = true): self` — stores the schema's array form under its name and records the name as required when `$required` is true.
- `withStringParameter(string $name, string $description, bool $required = true): self`
- `withNumberParameter(string $name, string $description, bool $required = true): self`
- `withBooleanParameter(string $name, string $description, bool $required = true): self`
- `withEnumParameter(string $name, string $description, array $options, bool $required = true): self`
- `withArrayParameter(string $name, string $description, Schema $items, bool $required = true): self`
- `withObjectParameter(string $name, string $description, array $properties, array $requiredFields = [], bool $allowAdditionalProperties = false, bool $required = true): self`
- `parameters(): array` — a map of parameter name to its schema array.
- `requiredParameters(): array` — the list of parameter names flagged as required.
