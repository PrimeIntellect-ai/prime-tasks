Provide access to read raw bytes in decoder
**Would you be amenable to adding a `read_bytes(length: usize)` method to the [`tiff::decoder::Decoder`](https://docs.rs/tiff/latest/tiff/decoder/struct.Decoder.html) struct?** This would be similar to the [`read_byte()`](https://docs.rs/tiff/latest/tiff/decoder/struct.Decoder.html#method.read_byte) method but would allow for more optimized reads by reading in a number of bytes from the underlying reader.

Use Case:
I have a use case where I want to access the raw bytes of the underlying TIFF file. In particular I want to be able to access the raw tiles/strips without decoding them (effectively [`read_chunk`](https://docs.rs/tiff/latest/tiff/decoder/struct.Decoder.html#method.read_chunk) but without decoding). This is a part of a file conversion process where I do not want to incur the data loss from decoding and re-encoding. Currently I am doing this by maintaining two copies of the Read + Seek object (e.g. two calls to `std::fs::File::open` or reading the file into memory and using two `std::io::Cursor`s on the data). I am able to get the tile offsets and byte counts (or strip offsets and byte counts) using the `tiff::decoder::Decoder` and then use the other reader to read the actual bytes. I can't reuse the reader I pass to `tiff::decoder::Decoder` due to ownership issues.

I did try repeated calls to [`goto_offset_u64`](https://docs.rs/tiff/latest/tiff/decoder/struct.Decoder.html#method.goto_offset_u64) and [`read_byte`](https://docs.rs/tiff/latest/tiff/decoder/struct.Decoder.html#method.read_byte), but it is prohibitively slow.

I'm happy to submit a PR if this `read_bytes(length: usize)` method sounds like something you would support!

Thank you for your work on this great project!

### Additional contract requirements

The public API to be added is `Decoder::inner(&mut self) -> &mut R`, which returns a mutable reference to the decoder's underlying reader (`R: Read + Seek`). Callers use it to perform raw `Read`/`Seek` operations on the source, e.g. seeking to a tile offset and reading the raw tile bytes directly.
