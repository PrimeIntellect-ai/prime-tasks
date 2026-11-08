Add `svelteSortOrder: none` option
Implement a new `svelteSortOrder` option which is called `none` and essentially leaves script/style/markup etc exactly where it is (other things like "shrink number of newlines to 1" would still apply).

This would close #111 and #258 by allowing an arbitrary number of comments inbetween sections.

### Additional contract requirements

When `svelteSortOrder` is `none`, excess blank lines between top-level sections are reduced to the formatter's usual single blank-line separation.
