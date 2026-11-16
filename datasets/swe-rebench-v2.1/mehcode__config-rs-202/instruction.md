[Feature request] Ron support
Would be nice if this crate supported [Rusty Object Notation](https://github.com/ron-rs/ron)

### Additional contract requirements

RON must be selectable as a file format through the existing API using `FileFormat::Ron`. Valid RON configuration documents must be available through ordinary configuration retrieval, deserialization, and conversion behavior. Malformed RON input must fail to parse.
