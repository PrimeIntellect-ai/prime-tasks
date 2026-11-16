bug: prevent decoding other CBOR types to `cbor.SimpleValue`
Currently, decoder can decode CBOR integers (not CBOR simple value) to `cbor.SimpleValue`.  However, CBOR simple value (major type 7) is different from integers and shouldn't be used interchangeably.

Fix this by only allowing CBOR simple values (major type 7) to be decoded to `cbor.SimpleValue`.
