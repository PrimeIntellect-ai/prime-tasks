Tags of type Short are read as Unsigned
When reading a tag that fits into the offset field and is of type `SHORT` (Tiff type 3) the value is returned as `Value::Unsigned` instead of `Value::Short`.

I believe the issue lies in [HIDDEN](https://github.com/image-rs/image-tiff/blob/aefea7786f038417632f72d861c0bf32bf6299ba/src/decoder/ifd.rs[HIDDEN]).

The right behavior is what can be seen when multiple values are handled ([HIDDEN](https://github.com/image-rs/image-tiff/blob/aefea7786f038417632f72d861c0bf32bf6299ba/src/decoder/ifd.rs[HIDDEN]))
