OCF: Hard to compose EncoderFuncs to modify metadata
`ocf.WithMetadata(meta map[string][]byte) EncoderFunc` exists to modify an OCF encoder to set metadata that gets written to the OCF header. This is useful, but hard to compose, since WithMetadata overwrites any previously-set metadata in the encoder configuration.

I propose that a new `ocf.WithMetadataKeyVal(key string, val []byte) EncoderFunc` would be useful to help here. This function would add a single key-value pair to the existing metadata, rather than overwriting it.

### Additional contract requirements

- Add a public function `WithMetadataKeyVal(key string, val []byte) EncoderFunc` in package `ocf`. When applied to an encoder configuration it sets the metadata entry named `key` to `val`, adding the entry if it is absent and updating it if it is already present, without affecting other metadata entries.
