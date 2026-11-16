Try and support PHP 7.1
**Is your feature request related to a problem? Please describe.**
In order to use JsonMapper in a version of Psalm, PHP7.1 support is needed.

**Describe the solution you'd like**
Ideally we should support older PHP versions in order to increase the number of potentials packages that can use this library.

**Describe alternatives you've considered**
None, lets just see if we can support PHP 7.1 without too many effort.

**Additional context**
None

### Additional contract requirements

The package must allow PHP 7.1 as a supported runtime, and the library's PHP code must be syntactically usable on PHP 7.1. Mapping APIs and the object wrapper must reject non-object values with a type error; the exact wording of that error is not prescribed.
