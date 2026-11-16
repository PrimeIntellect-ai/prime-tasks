Serialized Value cannot Deserialize
## Description

I'm using Value::from_serialize pass context to template. Then using `ViaDeserialize<Type>` deserialize the value. however, it failed.

here are some log:

<details>

```console
called `Result::unwrap()` on an `Err` value: Error { kind: CannotDeserialize, detail: "invalid type: map, expected enum Type", name: "op.idl", line: 24 }

----------------------------------- op.idl ------------------------------------
  22 |         {% for param in params %}
  24 >                 {{ param.ty | to_ty }} {{ param.ident }};
     i                               ^^^^^ cannot deserialize
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Referenced variables: {
    base_name: <macro base_name>,
    in_params: 0,
    loop: <loop 0/1>,
    param: {
        "ident": "com",
        "ty": {
            "Path": [
                "Command",
            ],
        },
    }
}

```
</details>

here is my enum defination:

```rs
enum Type {
    Array(TypeArray),
    Path(TypePath),
    Primative(PrimativeType),
}
```

as far as I know, plain enum, unit struct cannot be deserialize. It seems enum would be serialized to &str?

Additional helpful information:

- Version of minijinja: v2.1.1
- Version of rustc: 1.80.0
- Operating system and version: macos 14.5

## What did you expect

Serialization and deserialization operations should be symmetric
