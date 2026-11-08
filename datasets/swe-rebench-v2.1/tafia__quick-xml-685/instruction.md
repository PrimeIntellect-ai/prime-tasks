How to ignore double quotation mark when do serialization？
Before serialization:

r#""349DC700140D7F86A0784842780****""

After serialization:
> &quot349DC700140D7F86A0784842780****&quot

However, What expect:
"349DC700140D7F86A0784842780****"

How to ignore serializing double quotation mark?

### Additional contract requirements

- When serializing text content, emit apostrophes literally rather than as `&apos;`; for example, serializing `'` with a root element must produce `<root>'</root>`.
