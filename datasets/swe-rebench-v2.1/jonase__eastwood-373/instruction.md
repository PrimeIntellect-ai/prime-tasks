unused-ret-vals always warns about (is (thrown? Exception expr)) forms?
Because the expr's return value is ignored?  It seems pretty clear that the intention here is to verify that trying to evaluate the form throws an exception, so ignoring the return value seems quite reasonable here.  Try to find a precise way to disable such warnings in this case.

One example warning of this kind:

src/test/clojure/clojure/data/finger_tree/tests.clj:120:18: unused-ret-vals-in-try: Pure function call return value is discarded inside body of try: (assoc (apply counted-double-list (range len)) n :x)

Another example:

src/test/clojure/clojure/data/json_compat_0_1_test.clj:69:26: unused-ret-vals-in-try: Should use return value of function call, but it is discarded inside body of try: (read-json "{26:\"z\"")

It should be possible to eliminate these via the enclosing-macros customization technique already implemented for suspicious-expression and constant-test linters.  Overlap with #118 if so.

### Additional contract requirements

Eastwood must not report false-positive warnings for `clojure.test/is` forms. Linting a namespace that contains the following forms must produce no warnings:

- `(is (thrown? Exception (throws-exception)))` — no `unused-ret-vals` or `unused-ret-vals-in-try` warning for the expression whose return value is ignored.
- `(is (truthy? 42))`, where `truthy?` is a custom `clojure.test/assert-expr` — no `constant-test` warning.
- `(is (instance? String (func +)))` — no `suspicious-expression` warning.

In particular, linting the namespace `testcases.clojure-test` must return `{:some-warnings false}`.
