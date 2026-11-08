Allow excluding min/max in DoubleRangeFilter
**Is your feature request related to a problem? Please describe.**
We have a need to subdivide a continuous variable into ranges that are even and predicable, say, 0.0 - 4.0 into 4 buckets:
`[0.0, 1.0)  [1.0, 2.0), [2.0, 3.0), [3.0, 4.0)`
Each bucket with these boundaries would have no overlap. The current inclusive/inclusive boundaries make this very difficult to do without trying to hand make the boundaries to be hopefully close enough but not equal to the next value that there will not be another value in between the ending of one bucket and the start of the next one ie:
`[0.0, 0.99999999...], [1, 1.99999999...]`

We also have used this type of representation for discrete values as well (like enumerations) where it is even more important that the buckets do not overlap.

**Describe the solution you'd like**
We propose no default changes to how things work, by default a query would still run with min/max as inclusive boundaries.

However, we propose adding a new field to the DoubleRangeFilter contract that introduces the idea that either or both bounds could be exclusive:
```
message DoubleRangeFilter {
  // Name of the ticket's search_fields.double_args this Filter operates on.
  string double_arg = 1;

  // Maximum value.
  double max = 2;

  // Minimum value.
  double min = 3;

  enum Exclude {
    NONE = 0;
    MIN = 1;
    MAX = 2;
    BOTH = 3;
  }
  Exclude exclude = 4;
}
```
This will enable all of the scenarios we currently use and more

**Describe alternatives you've considered**
An alternative to achieve this is attempt to understand the minimum value between the discrete bucket ranges and do some math that will hopefully be close enough to the next buckets minimum range that there is no possibility of a value existing between it. The main concern here is that the computation of these ranges may be done on different platform architectures and may result in slightly varying results at high precision:
So instead of the desired list of filters for a few non overlapping queries:
`[0.0, 1.0)  [1.0, 2.0), [2.0, 3.0), [3.0, 4.0)`
We could try:
`[0.0, 0.99999999...)  [1.0, 1.9999999...), [2.0, 2.9999999...), [3.0, 3.99999999...)`

This has the potential to miss some values between the max of one range and the next range, in addition to being cumbersome to compute and look at compared to the mathematically concise way of defining these.

**Additional context**
We currently run a matchmaker that we would like to port over to using open match as the ticket backend; our existing logic for generating queries that is exposed to customers has the behavior we describe, and it would be a breaking change we would like to avoid to have to convey to customers that they will now need to simulate ranges like this.
