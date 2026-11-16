Should `Validity::decode_value` error when `GeneralizedTime` is used for dates before 2050?
[RFC 5280 § 4.1.2.5.](https://www.rfc-editor.org/rfc/rfc5280#section-4.1.2.5) requires all dates before 2050 to be encoded as UTCTime:

> CAs conforming to this profile MUST always encode certificate validity dates through the year 2049 as UTCTime

however that is not enforced by `Validity::decode_value`. Similarly `Validity::encode_value` encodes without erring or implicitly converting such a `GeneralizedTime` into a `UtcTime` despite the RFC requiring it.

### Additional contract requirements

- Serializing a `Validity` must comply with RFC 5280 § 4.1.2.5: a validity date through the year 2049 must be encoded as UTCTime, and a date in 2050 or later must be encoded as GeneralizedTime. In particular, a `Validity` whose date is before 2050 but is held as a `GeneralizedTime` must be serialized as UTCTime.
- Parsing is left untouched: decoding a `Validity` does not enforce the RFC 5280 time-encoding restriction, so a pre-2050 date encoded as GeneralizedTime still decodes successfully.
