feature: Add decoder option (non-default) to allow decoding CBOR text string containing invalid UTF-8
This new option would allow users to override the default setting and decode CBOR text string containing invalid UTF-8.

The encoder allows encoding invalid UTF-8 to CBOR text string because CBOR RFC 8949 states:

> Generic CBOR encoders provide an application interface that allows the application to specify any well-formed value to be encoded as a CBOR data item, including simple values and tags unknown to the encoder.
>
>Even though CBOR attempts to minimize these cases, not all well-formed CBOR data is valid: for example, the encoded text string 0x62c0ae does not contain valid UTF-8 (because [RFC3629] requires always using the shortest form) and so is not a valid CBOR item.

The decoder currently checks and prevents decoding CBOR text string containing invalid UTF-8.

Although I recommend specifying or using protocols that reject invalid UTF-8 strings in CBOR text strings, some scenarios might find it useful.

### Additional contract requirements

Expose the opt-in decoder setting through `DecOptions.UTF8`, using `UTF8DecodeInvalid` to accept invalid UTF-8 text strings. `UTF8RejectInvalid` represents rejection; rejection must also remain the behavior when the option is left at its zero/default value. With decoding enabled, the resulting Go string preserves the text string's bytes, including invalid UTF-8 bytes. Valid UTF-8 text strings must continue to decode successfully with either setting.
