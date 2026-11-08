Debug assertion triggered on empty doctype
Thank you for quick-xml and sorry for comming back with an other bug.

When parsing the file `<!DoctyPE>` using rusc "dev" profile the assertion `"DocType must have a name"` is triggered. In the "release" profile the assertion is not triggered and the parser returns an empty `Event::Doctype()`

Test failing in "dev" profile and passing in "release" profile:
```rust
#[test]
fn reproduce() {
    let data = b"<!DoctyPE>";
    let mut reader = Reader::from_reader(data.as_slice());
    let mut buf = Vec::new();
    loop {
        match reader.read_event_into(&mut buf) {
            Ok(Event::Eof) => break,
            Ok(Event::DocType(e)) => assert!(e.is_empty()), // assertion only executed in "release" mode
            _ => unreachable!()
        }
    }
}
```

### Additional contract requirements

- Parsing the exact input `<!DoctyPE>` (an empty `<!DOCTYPE>` declaration with no
  name and no whitespace before the closing `>`) must return `Error::EmptyDocType`
  from `Reader::read_event_into`, instead of triggering the debug assertion or
  yielding an empty `Event::DocType`.
- The same applies to an empty doctype that contains only whitespace before the
  closing `>`, such as `<!doctype  \n    >`.
