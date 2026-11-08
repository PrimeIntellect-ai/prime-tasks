Unexpected empty `Text` event when XML starts from a comment
I noticed, that such XML generates an empty `Text` event that is redundant:
```xml
<!---->
```

The following tests failed (if placed into [`reader.rs`](https://github.com/tafia/quick-xml/blob/master/src/reader.rs)):
```rust
#[cfg(test)]
mod test {
    use super::*;
    use crate::reader::Reader;

    #[test]
    fn start_with_comment_buffered() {
        let mut reader = Reader::from_str("<!---->other content");

        /*assert_eq!(
            reader.read_event_buffered(&mut Vec::new()).unwrap(),
            Event::Text(BytesText::from_escaped(b"".as_ref()))
        );*/
        assert_eq!(
            reader.read_event_buffered(&mut Vec::new()).unwrap(),
            Event::Comment(BytesText::from_escaped(b"".as_ref()))
        );
        assert_eq!(
            reader.read_event_buffered(&mut Vec::new()).unwrap(),
            Event::Text(BytesText::from_escaped(b"other content".as_ref()))
        );
    }

    #[test]
    fn start_with_comment_unbuffered() {
        let mut reader = Reader::from_str("<!---->other content");

        /*assert_eq!(
            reader.read_event_buffered(()).unwrap(),
            Event::Text(BytesText::from_escaped(b"".as_ref()))
        );*/
        assert_eq!(
            reader.read_event_buffered(()).unwrap(),
            Event::Comment(BytesText::from_escaped(b"".as_ref()))
        );
        assert_eq!(
            reader.read_event_buffered(()).unwrap(),
            Event::Text(BytesText::from_escaped(b"other content".as_ref()))
        );
    }
}
```
If you uncomment commented checks, then tests will pass.

There no need to generate redundant empty `Text` events, because otherwise we can say, why only one such event is generated? In my opinion empty `Text` event should be _never_ generated
