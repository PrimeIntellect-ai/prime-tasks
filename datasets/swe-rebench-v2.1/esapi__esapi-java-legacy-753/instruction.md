JSON encoder
Implement a JSON output encoder to encode data for use in JSON strings as per [Section 7 of RFC 8259](https://datatracker.ietf.org/doc/html/rfc8259#section-7).

**Is your feature request related to a problem? Please describe.**
@noloader needs it for his $dayjob.

**Describe the solution you'd like**
Provided as PR #753

**Describe alternatives you've considered including other security libraries**
Using JavaScript to to the dirty work. That path was rejected because different implementations support slightly different grammars.

### Additional contract requirements

Expose the JSON output encoder through the public method name `Encoder.encodeForJSON(String)`. Its result must be valid JSON string contents as specified by RFC 8259 Section 7.
