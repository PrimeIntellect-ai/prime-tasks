Support X12 ISX Segment Release Character

X12 TR4 (Clarification Paper)

> The ISX segment first appeared in version/release 007040 of the X12 EDI Standard, with ISX01 and ISX02. ISX03 and ISX04 were introduced in version/release 008010. The I11 value in the ISA segment determines the version of the ISX which may be used in the interchange.

The elements features in ISX are listed below. This issue will address the first element.
1. Release Character - ISX01
2. Character Encoding - ISX02
3. Overriding X12 Version / Release Code - ISX03
4. Industry Identifier - ISX04

### Additional contract requirements

- When an ISX segment appears with ISA I11 value `00401` or `00501`, report exactly one `UNEXPECTED_SEGMENT` validation error. For ISA I11 value `00704`, an ISX01 value longer than one character must report exactly one `DATA_ELEMENT_TOO_LONG` validation error.
- - When ISA I11 is `00704` and ISX01 is longer than one character, `getDelimiters()` must omit `Delimiters.RELEASE`.
