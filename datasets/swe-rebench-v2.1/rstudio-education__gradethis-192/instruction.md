Messages unpipe internal enclosing calls
When a message prints the enclosing call, the call should appear as the student wrote it. If the call uses a pipe, so should the message. Here's how things currently break:

```r
# test_detect_matches line 467
  user <-     quote(a(2 %>% abs() %>% sqrt())) # nolint
  solution <- quote(a(2 %>% log() %>% sqrt())) # nolint
  expect_equal(
    detect_mistakes(user, solution),
    wrong_call(this = user[[2]][[2]][[3]], that = solution[[2]][[2]][[3]], enclosing_call = user[[2]])
  )
# Error: detect_mistakes(user, solution) not equal to wrong_call(...).
# 1/1 mismatches
# x[1]: "In sqrt(abs(2)), I expected you to call log() where you called abs()."
# y[1]: "In 2 %>% abs() %>% sqrt(), I expected you to call log() where you called
# y[1]:  abs()."
```

### Additional contract requirements

- When comparing `b(1 %>% abs())` with `b(1)`, the feedback should be exactly: `In \`b(1 %>% abs())\`, I expected \`1\` where you wrote \`1 %>% abs()\`.`
