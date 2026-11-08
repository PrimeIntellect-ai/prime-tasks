feat: Optional Macro Stack Syntax
## Overview

Often-times, developers write macros that take/return no stack items.

This creates unnecessary boilerplate code required by the developer in the form of `= takes (0) returns (0)`.

We should make the `takes` and `returns` annotations optional (NOTE: Maybe also allow for just declaring one?) so `#define macro MAIN()` would be equivalent to `#define macro MAIN() = takes (0) returns (0)`.

### Additional contract requirements

- The `takes` and `returns` annotations are each independently optional. A macro
  definition may specify both annotations, only `takes`, only `returns`, or
  neither.
- An omitted annotation defaults to `0`. For example,
  `#define macro MAIN() = takes(3) {}` is equivalent to
  `#define macro MAIN() = takes(3) returns(0) {}`, and
  `#define macro MAIN() = returns(10) {}` is equivalent to
  `#define macro MAIN() = takes(0) returns(10) {}`.
