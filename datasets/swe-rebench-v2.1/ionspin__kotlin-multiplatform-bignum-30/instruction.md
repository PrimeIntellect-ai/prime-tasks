Support Ranges
**Is your feature request related to a problem? Please describe.**
For convenience it would be nice to support Range's for BigInteger's, for example by providing the infix.

**Describe the solution you'd like**
Just for convenience, non-blocking

**Describe alternatives you've considered**
Convert to Int before setting the range.
I did not research if this is a easy job. Just wanted to add the feature request in case it is possible.

**Additional context**
https://kotlinlang.org/api/latest/jvm/stdlib/kotlin.ranges/index.html
https://kotlinlang.org/api/latest/jvm/stdlib/kotlin.ranges/until.html

### Additional contract requirements

- A BigInteger range created with Kotlin’s `..` syntax is iterable, yielding successive integer values from its start through its inclusive end.
