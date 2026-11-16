Text events are not emitted when text node ends exactly at BufferedReader buffer border
Perhaps the title isn't quite clear here. As a concrete example, the document written by this python script:

```py
open('test.xml', 'w').write('<asdf>' + 'a' * (8192 - 6) + '</asdf>')
```

(i.e., a document with a single tag, whose contents end at offset 8192) will cause quick-xml to emit only a Start and End event, with no Text event in the middle. This can be verified with the following rust program, which simply dumps all received events to stderr:

```rs
use quick_xml::events::Event;
use quick_xml::reader::Reader;

fn main() {
    let mut reader = Reader::from_file("test.xml").unwrap();
    let mut buf = Vec::new();
    loop {
        let ev = reader.read_event_into(&mut buf);
        if matches!(ev, Ok(Event::Eof)) { break; }
        dbg!(&ev);
    }
}
```

This prints:

```
[src/main.rs:10:9] &ev = Ok(
    Start(
        BytesStart { buf: Borrowed("asdf"), name_len: 4 },
    ),
)
[src/main.rs:10:9] &ev = Ok(
    End(
        BytesEnd { name: Borrowed("asdf") },
    ),
)
```

---

The root cause seems to be [HIDDEN]. In this case, reading the text data requires two loop iterations. On the first iteration, `<` is not found in the data, so the entire data is pushed onto `buf` and the loop continues. [HIDDEN]

[HIDDEN]

### Additional contract requirements

- When non-empty character data is immediately followed by markup, quick-xml must emit a `Text` event for that data before the following markup event, including when the text ends exactly at a buffered-reader boundary.
