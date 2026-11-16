Warning about string-typed filter values seems problematic
There are a number of standard CodeSystem filters defined in the FHIR spec, such as https://hl7.org/fhir/snomedct.html#4.3.1.0.8.3, but when I use these in my FSH files to define ValueSets, I'm getting the very concerning warning:

> The match value of filter operator "=" must be a code. For string valued properties, use the regex filter operator with a regular expression value. Support for using strings as filter values has been deprecated and will be removed in a future release.

Do I need to worry that these standard filters are going to be unusable in some upcoming version of Sushi?

### Additional contract requirements

- String-valued `=` filters remain supported, and parsing them does not emit a deprecation warning claiming that support for strings as filter values will be removed.
- String literals are accepted for every supported ValueSet filter operator, in addition to each operator's typed values. For `exists`, only the string literals `"true"` and `"false"` are accepted; boolean values remain accepted as well.
- A filter value that is neither an accepted typed value for its operator nor an accepted string value for that operator is rejected and is not emitted as a filter.
