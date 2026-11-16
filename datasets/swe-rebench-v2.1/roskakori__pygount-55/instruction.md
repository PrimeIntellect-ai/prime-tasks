List for exceptions in the plain_text regex
Files like `CMakeLists.txt` fall into `pygount`'s plain_text reg-ex check, gets classified as `Text`, and counted as comment. We could modify the part [here](https://github.com/roskakori/pygount/blob/43137b40b4030c09cf64bb2a8da9efd50adcebab/pygount/analysis.py#L122) as,
[HIDDEN]
and fix this.

P.S. although this will make `CMakeLists.txt` count as code, it'll still get listed as `Text Only`. But that is a [bug in pygments/guess_lexer_for_filename](https://github.com/pygments/pygments/issues/523).

### Additional contract requirements

- `pygount.analysis.guess_lexer(filename: str, source_code: str)` returns the Pygments lexer that matches the given file.
- For a `CMakeLists.txt` file containing typical CMake commands, the returned lexer's `name` is `"CMake"`.
- A `CMakeLists.txt` file containing typical CMake commands must be analyzed as code rather than plain text or comments; its code count must be positive and its documentation count must be zero.
