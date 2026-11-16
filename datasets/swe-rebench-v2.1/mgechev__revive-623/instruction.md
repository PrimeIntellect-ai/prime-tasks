Rule 'var-naming' should allow Fuzz_xxx()
**Is your feature request related to a problem? Please describe.**
In Go 1.18, [fuzzing is officially supported](https://go.dev/doc/fuzz/). FuzzXxx should be treated as same as TestXxx, BenchmarkXxx, ExampleXxx, which can use underscore(`_`) in the function name.
For example, if you are developing `big.Int` and add a fuzz test to `big.Int.SetString`, the test function's name will be `FuzzInt_SetString`.

**Describe the solution you'd like**
I haven't tested it, but [HIDDEN]
