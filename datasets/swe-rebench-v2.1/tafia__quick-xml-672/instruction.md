xml serde read translates optional attributes with value "" to None
If you want to be able to make a difference between attribute missing and attribute empty `""` should serialize to `Some("")` but those attributes deserialize to `None`.
(useful for roundtrips where the output should be equal to input with small change applied)

```rust
use serde::{Deserialize, Serialize};

#[derive(Debug, Deserialize, Serialize, PartialEq, Eq)]
struct Name {
    #[serde(rename = "@first_name", skip_serializing_if = "Option::is_none")]
    first_name: Option<String>,
    #[serde(rename = "@second_name", skip_serializing_if = "Option::is_none")]
    second_name: Option<String>,
}

#[test]
fn read_and_write() {
    let expected = Name {
        first_name: Some("aaa".to_string()),
        second_name: Some("".to_string()),
    };

    let name =
        quick_xml::de::from_str::<Name>(r#"<Name first_name="aaa" second_name=""/>"#).unwrap();

    assert_eq!(expected, name);

    let s = quick_xml::se::to_string(&name).unwrap();

    assert_eq!(r#"<Name first_name="aaa" second_name=""/>"#, s);
}
```

fails with

```
thread 'read_and_write' panicked at tests/tezt.rs:21:5:
assertion `left == right` failed
  left: Name { first_name: Some("aaa"), second_name: Some("") }
 right: Name { first_name: Some("aaa"), second_name: None }
note: run with `RUST_BACKTRACE=1` environment variable to display a backtrace
```

I found similar issues that are marked as fixed: #252 and #527
