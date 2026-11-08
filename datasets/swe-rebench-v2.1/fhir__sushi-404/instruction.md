base64Binary regex may be wrong
The regular expression we use to validate `base64Binary` strings is `(\s*([0-9a-zA-Z\+\=]){4}\s*)+`, which we copied directly from https://www.hl7.org/fhir/datatypes.html#primitive. However, this regex seems incorrect. It does not allow the `/` character, which is used in base64 binary encoding. In the FHIR XML schemas, a different regex is used: `[HIDDEN]`. This regular expression *does* allow for the `/` character. [HIDDEN]

### Additional contract requirements

- `base64Binary` validation must accept `/` in otherwise-valid Base64-encoded values.
