from_str should ignore encoding in XML declaration
XML can be viewed as a binary format, for instance when parsed using from_reader from a sequence of bytes.
However, when parsing from a &str, the content is already guaranteed to be valid UTF-8.
In that case the encoding hint in the XML declaration should be ignored.

Here is a test that fails (make sure the source code is saved as UTF-8).

```rust
#[test]
fn from_str_should_ignore_encoding() {
    let xml = r#"
        <?xml version="1.0" encoding="windows-1252" ?>
        <A a="€" />
    "#;

    #[derive(Debug, PartialEq, Deserialize)]
    struct A {
        a: String,
    }

    let a: A = quick_xml::de::from_str(xml).unwrap();
    assert_eq!(
        a,
        A {
            a: "€".to_string()
        }
    );
}
```

Test result:
```
---- foo::from_str_should_ignore_encoding stdout ----
thread 'foo::from_str_should_ignore_encoding' panicked at 'assertion failed: `(left == right)`
  left: `A { a: "â‚¬" }`,
 right: `A { a: "€" }`', src/foo.rs:415:5
note: run with `RUST_BACKTRACE=1` environment variable to display a backtrace
```
