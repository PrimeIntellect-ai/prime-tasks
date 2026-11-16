Raw struct names cannot be deserialised
```rust
use ron::Error;
use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize, PartialEq, Eq, Debug)]
#[serde(rename = "Hello+World")]
struct RawStruct {
    #[serde(rename = "ab.cd-ef")]
    field: bool,
}

#[test]
fn test_raw_identifier_roundtrip() {
    let val = RawStruct { field: true };

    let ser =
        ron::ser::to_string_pretty(&val, ron::ser::PrettyConfig::default().struct_names(true))
            .unwrap();
    assert_eq!(ser, "r#Hello+World(\n    r#ab.cd-ef: true,\n)");

    // Fails with an error that "Hello+World" was expected but "Hello+World" was found
    let de: RawStruct = ron::from_str(&ser).unwrap();
    assert_eq!(de, val);
}

```

### Additional contract requirements

- Support raw-identifier syntax (`r#...`) for struct names, field names, and enum variant names. Match the identifier text against the corresponding Serde-configured name, and allow values using such names to round-trip.
- When serializing a name that requires raw-identifier syntax, emit it in that form. If a name cannot be represented as a valid raw identifier, fail with `Error::InvalidIdentifier`.
- When an unprefixed name is invalid as a standard identifier but valid as a raw identifier, report `Error::SuggestRawIdentifier` with the identifier.
- Preserve semantically appropriate deserialization errors for empty input to an unnamed unit struct, a missing named-struct identifier, a mismatched struct name, and unknown struct fields or enum variants. Use the corresponding error categories `ExpectedUnit`, `ExpectedNamedStructLike`, `ExpectedDifferentStructName`, `NoSuchStructField`, and `NoSuchEnumVariant`.
