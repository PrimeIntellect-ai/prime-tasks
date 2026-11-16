Property names starting with digits
Using the JSONata exerciser at http://try.jsonata.org - not sure which version that is.

data {"7a":33, "a7":55, "7":88}:

7a -> Syntax error: “a”
“7a” -> “7a”
`7a` -> 33

$.7a -> Syntax error: “a”
$.“7a” -> 33
$.`7a` -> 33

but:

$.7 -> 88

It seems inconsistent to allow $.7 but not $.7a unquoted (or unticked).  Identifiers which start with a digit should be treated the same way regardless of whether they consist entirely of digits or only partly, in my opinion.  I prefer that they should need to be enclosed.

### Additional contract requirements

- An unquoted digit-leading path step such as `$.7` must be rejected with error code `S0213`.
- An unquoted identifier that starts with a digit but contains non-digit characters, such as `$.7a`, must also be rejected (digit-leading identifiers require enclosure); the parser reports this as error code `S0201`.
