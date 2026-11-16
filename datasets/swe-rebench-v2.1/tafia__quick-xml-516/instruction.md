Incorrect example of temporary disabling `check_end_names`
The example
https://github.com/tafia/quick-xml/blob/92de42ee15149a683357e5e690bc01229c6b82ec/src/reader/slice_reader.rs#L203-L217
for [`read_text`](https://docs.rs/quick-xml/latest/quick_xml/reader/struct.Reader.html#method.read_text) is incorrect -- doing that will leave reader in incorrect state and you'll get a wrong `EndEventMismatch` error next time when you'll read surrounding `End` event:

```xml
<some-tag>
  <event>
    <!-- You decided to .check_end_names(false) after seeing "<event>" -->
    ...
  </event>
  <!-- You decided to .check_end_names(true) after seeing "</event>" -->
</some-tag><!-- EndEventMismatch { expected "event", found: "some-tag" } -->
```

### Additional contract requirements

- For `<some-tag><html>...</html></other-tag>`, after reading the `<some-tag>` and `<html>` start events, setting `check_end_names(false)`, calling `read_text` with the `html` end name, and setting `check_end_names(true)`, the next `read_event()` must return `Error::EndEventMismatch { expected: "some-tag", found: "other-tag" }`, and the following `read_event()` must return `Event::Eof`.
