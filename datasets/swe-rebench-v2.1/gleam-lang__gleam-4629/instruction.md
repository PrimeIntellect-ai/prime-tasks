Variable completion goes out of case arm bounds
<!--
Please include the following:
- Steps and code to reproduce the problem
- Versions for Gleam, OS, the runtime and any other software used
- Logs from running Gleam with the `GLEAM_LOG` environment variable set to `trace`
-->
Given this code, with the cursor inside the `False, bar` block:
```gleam
pub fn main() {
  let first = {
    True == True
  }
  let second = 3

  case first, second {
    True, foo -> {
      let x = 1
    }
    False, bar -> {
      |
    }
  }
}
```
The language server completes both `foo` and `x` as valid symbols. However, they're not, since they're in another arm of the case statement. I was able to reproduce this on both 0.10 and 0.11-rc, so it's not been introduced in the last cycle.

### Additional contract requirements

Completion results must not include local variables bound by a case arm when the cursor is in a different arm or after the case expression. This applies to variables introduced by either the arm pattern or its body.
