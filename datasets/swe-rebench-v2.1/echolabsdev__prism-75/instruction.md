Nullable Schema types
Hi, thanks for the awesome library!

I was testing structured outputs and found a limitation.

[Because all fields must be required in the schema](https://platform.openai.com/docs/guides/structured-outputs#all-fields-must-be-required), OpenAI recommends making the type a nullable union if one wants an "optional" field.

```diff
{
    "name": "get_weather",
    "description": "Fetches the weather in the given location",
    "strict": true,
    "parameters": {
        "type": "object",
        "properties": {
            "location": {
                "type": "string",
                "description": "The location to get the weather for"
            },
            "unit": {
+               "type": ["string", "null"],
                "description": "The unit to return the temperature in",
                "enum": ["F", "C"]
            }
        },
        "additionalProperties": false,
        "required": [
            "location", "unit"
        ]
    }
}
```

As far as I understand, this is not possible with the current Schema objects, right? Would be nice if it could be added in the future. :)

### Additional contract requirements

Each schema class (`StringSchema`, `NumberSchema`, `BooleanSchema`, `ArraySchema`, `ObjectSchema`, and `EnumSchema`) accepts a final optional boolean constructor argument named `nullable`, defaulting to `false`. Passing `true` makes the serialized schema type include `null` alongside its underlying JSON Schema type. For enum schemas, this preserves the declared enum values and description. Making a property schema nullable does not remove that property from its containing object's required-field list.
