Z shaping: handle sets and arrays (for "deep json")
The shaper functions introduced in #1984 do not handle arrays and sets. This issue consists of adding that support. This is likely to be useful particular for "deep json" where arrays of objects are common.
