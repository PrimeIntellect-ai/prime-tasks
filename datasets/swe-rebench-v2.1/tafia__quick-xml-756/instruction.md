Processing instructions should have a dedicated type
Currently we use `BytesText` for them, but this is a text that represents a text with character and entity references, but that references [MUST NOT be recognized within processing instructions](https://www.w3.org/TR/xml11/#sec-pi).

### Additional contract requirements

- The payload of a processing-instruction event (`Event::PI`) is a dedicated type, `quick_xml::events::BytesPI`, and not `BytesText`.
- `BytesPI::target()` returns the target name: the bytes before the first whitespace character or the closing `?>`. It is empty for `<??>`.
- `BytesPI::content()` returns everything after the target name up to the closing `?>`, exactly as written in the input. This includes leading and trailing whitespace.
- Character references (such as `&#65;`) and entity references (such as `&amp;`) inside a processing instruction are kept as literal text in its content and are not expanded.
- Whitespace trimming options of the reader do not alter the content of a processing instruction.
- Empty processing instructions (`<??>`) and processing instructions with only a target (`<?xmlx?>`) are reported as processing-instruction events, not as errors.
