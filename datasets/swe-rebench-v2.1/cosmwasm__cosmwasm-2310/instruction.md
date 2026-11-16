schema_for! on HashMap and BTreeMap no longer generates field information for values
Sorry for the confusing title, allow me to demonstrate. I bisected this issue down to the commit:

https://github.com/CosmWasm/cosmwasm/commit/e4700750e12fe7f0e5b4ab157e4a085f192358b1

You can see the issue with this code:

```rust
use cosmwasm_schema::cw_serde;
use std::collections::BTreeMap;

#[cw_serde]
struct HasMap {
    map_field: BTreeMap<String, u32>,
    normal_field: u32,
}

fn main() {
    let schema = cosmwasm_schema::schema_for!(HasMap);
    println!("{schema:#?}");
}
```

With cosmwasm-schema version 2.0.2, the output I receive is:

<details>

```json
RootSchema {
    meta_schema: Some(
        "http://json-schema.org/draft-07/schema#",
    ),
    schema: SchemaObject {
        metadata: Some(
            Metadata {
                id: None,
                title: Some(
                    "HasMap",
                ),
                description: None,
                default: None,
                deprecated: false,
                read_only: false,
                write_only: false,
                examples: [],
            },
        ),
        instance_type: Some(
            Single(
                Object,
            ),
        ),
        format: None,
        enum_values: None,
        const_value: None,
        subschemas: None,
        number: None,
        string: None,
        array: None,
        object: Some(
            ObjectValidation {
                max_properties: None,
                min_properties: None,
                required: {
                    "map_field",
                    "normal_field",
                },
                properties: {
                    "map_field": Object(
                        SchemaObject {
                            metadata: None,
                            instance_type: Some(
                                Single(
                                    Object,
                                ),
                            ),
                            format: None,
                            enum_values: None,
                            const_value: None,
                            subschemas: None,
                            number: None,
                            string: None,
                            array: None,
                            object: Some(
                                ObjectValidation {
                                    max_properties: None,
                                    min_properties: None,
                                    required: {},
                                    properties: {},
                                    pattern_properties: {},
                                    additional_properties: Some(
                                        Object(
                                            SchemaObject {
                                                metadata: None,
                                                instance_type: Some(
                                                    Single(
                                                        Integer,
                                                    ),
                                                ),
                                                format: Some(
                                                    "uint32",
                                                ),
                                                enum_values: None,
                                                const_value: None,
                                                subschemas: None,
                                                number: Some(
                                                    NumberValidation {
                                                        multiple_of: None,
                                                        maximum: None,
                                                        exclusive_maximum: None,
                                                        minimum: Some(
                                                            0.0,
                                                        ),
                                                        exclusive_minimum: None,
                                                    },
                                                ),
                                                string: None,
                                                array: None,
                                                object: None,
                                                reference: None,
                                                extensions: {},
                                            },
                                        ),
                                    ),
                                    property_names: None,
                                },
                            ),
                            reference: None,
                            extensions: {},
                        },
                    ),
                    "normal_field": Object(
                        SchemaObject {
                            metadata: None,
                            instance_type: Some(
                                Single(
                                    Integer,
                                ),
                            ),
                            format: Some(
                                "uint32",
                            ),
                            enum_values: None,
                            const_value: None,
                            subschemas: None,
                            number: Some(
                                NumberValidation {
                                    multiple_of: None,
                                    maximum: None,
                                    exclusive_maximum: None,
                                    minimum: Some(
                                        0.0,
                                    ),
                                    exclusive_minimum: None,
                                },
                            ),
                            string: None,
                            array: None,
                            object: None,
                            reference: None,
                            extensions: {},
                        },
                    ),
                },
                pattern_properties: {},
                additional_properties: Some(
                    Bool(
                        false,
                    ),
                ),
                property_names: None,
            },
        ),
        reference: None,
        extensions: {},
    },
    definitions: {},
}
```

</details>

But with version 2.1.2, instead I get:

<details>

```json
RootSchema {
    meta_schema: Some(
        "http://json-schema.org/draft-07/schema#",
    ),
    schema: SchemaObject {
        metadata: Some(
            Metadata {
                id: None,
                title: Some(
                    "HasMap",
                ),
                description: None,
                default: None,
                deprecated: false,
                read_only: false,
                write_only: false,
                examples: [],
            },
        ),
        instance_type: Some(
            Single(
                Object,
            ),
        ),
        format: None,
        enum_values: None,
        const_value: None,
        subschemas: None,
        number: None,
        string: None,
        array: None,
        object: Some(
            ObjectValidation {
                max_properties: None,
                min_properties: None,
                required: {
                    "map_field",
                    "normal_field",
                },
                properties: {
                    "map_field": Object(
                        SchemaObject {
                            metadata: None,
                            instance_type: Some(
                                Single(
                                    Object,
                                ),
                            ),
                            format: None,
                            enum_values: None,
                            const_value: None,
                            subschemas: None,
                            number: None,
                            string: None,
                            array: None,
                            object: Some(
                                ObjectValidation {
                                    max_properties: None,
                                    min_properties: None,
                                    required: {},
                                    properties: {},
                                    pattern_properties: {},
                                    additional_properties: Some(
                                        Bool(
                                            false,
                                        ),
                                    ),
                                    property_names: None,
                                },
                            ),
                            reference: None,
                            extensions: {},
                        },
                    ),
                    "normal_field": Object(
                        SchemaObject {
                            metadata: None,
                            instance_type: Some(
                                Single(
                                    Integer,
                                ),
                            ),
                            format: Some(
                                "uint32",
                            ),
                            enum_values: None,
                            const_value: None,
                            subschemas: None,
                            number: Some(
                                NumberValidation {
                                    multiple_of: None,
                                    maximum: None,
                                    exclusive_maximum: None,
                                    minimum: Some(
                                        0.0,
                                    ),
                                    exclusive_minimum: None,
                                },
                            ),
                            string: None,
                            array: None,
                            object: None,
                            reference: None,
                            extensions: {},
                        },
                    ),
                },
                pattern_properties: {},
                additional_properties: Some(
                    Bool(
                        false,
                    ),
                ),
                property_names: None,
            },
        ),
        reference: None,
        extensions: {},
    },
    definitions: {},
}
```

</details>

Since that's a lot of content, here's the diff between the two:

```diff
<                                         Object(
<                                             SchemaObject {
<                                                 metadata: None,
<                                                 instance_type: Some(
<                                                     Single(
<                                                         Integer,
<                                                     ),
<                                                 ),
<                                                 format: Some(
<                                                     "uint32",
<                                                 ),
<                                                 enum_values: None,
<                                                 const_value: None,
<                                                 subschemas: None,
<                                                 number: Some(
<                                                     NumberValidation {
<                                                         multiple_of: None,
<                                                         maximum: None,
<                                                         exclusive_maximum: None,
<                                                         minimum: Some(
<                                                             0.0,
<                                                         ),
<                                                         exclusive_minimum: None,
<                                                     },
<                                                 ),
<                                                 string: None,
<                                                 array: None,
<                                                 object: None,
<                                                 reference: None,
<                                                 extensions: {},
<                                             },
---
>                                         Bool(
>                                             false,
```

Note that the old version correctly generated schema information indicating that the contents of the field are an Object with `uint32`s as values. Without this, the generated schemas are missing that information, which ultimately (in our use case) leads to incorrectly generated TypeScript types.
