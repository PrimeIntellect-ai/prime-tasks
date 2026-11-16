Implicit integer wrapping on deserialization causes wrong values
First, thanks a lot for this crate! I have used it for over a year in [godot-rust](https://github.com/godot-rust/gdext) and am very happy about the dependency-free tree and fast CI times. I wish more crates would follow such a lightweight approach 💪

Now we encountered an issue that caused a follow-up bug in our code.
Minimal reproducible example:
```rs
use nanoserde::DeJson;

#[derive(DeJson, Clone)]
pub struct EnumConstant {
    pub max: i32,
    pub zero: i32,
    pub min: i32,
}

#[test]
fn test() {
    let json = r#"{"max": 4294967295, "zero": 4294967296, "min": 4294967297}"#;
    let constant: EnumConstant = DeJson::deserialize_json(json).unwrap();
    assert_eq!(constant.max, -1);
    assert_eq!(constant.zero, 0);
    assert_eq!(constant.min, 1);
}
```

This test passes, but should not in my opinion. If a value is not representable in the target type, deserialization should fail. That's the only way I can know that my data model is inaccurate -- otherwise it's very easy to introduce silent logic errors.
