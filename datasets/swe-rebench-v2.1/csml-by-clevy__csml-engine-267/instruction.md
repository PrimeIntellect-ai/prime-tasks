index as optional parameter for iterators
**Is your feature request related to a problem? Please describe.**
 Currently there is no easy way to access the index will using iterators

 [1, 2].map( (value) {
  ...
 })

**Describe the solution you'd like**

Allow access of index as optional parameter

 [1, 2].map( (value, index) {
  ...
 })

### Additional contract requirements

For `map` and `filter`, a callback may declare a second parameter to receive the zero-based index of the current element. For `reduce`, a callback may declare a third parameter to receive the zero-based index of the current element, following the accumulator and element parameters. These index parameters may be omitted when they are not needed.
