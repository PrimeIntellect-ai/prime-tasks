Global fail.hint = TRUE + fail() = doubled hints
When I run the tutorial below, I receive a duplicated code hint in the feedback message. We should change this to a single code hint.

````
---
output: learnr::tutorial
runtime: shiny_prerendered
---

```{r setup, include=FALSE}
library(learnr)
library(gradethis)

gradethis_setup(
  fail.hint = TRUE,      # Give a code feedback hint on all fail*()? Remove if not desired
  fail.encourage = TRUE, # Encourage on all fail*()
  pass.praise = TRUE     # Praise on all pass*()
)
```

Type 1.


```{r yo, exercise = TRUE}

```

```{r yo-solution}
1
```

```{r yo-check}
grade_this({
  pass_if_equal()
  fail()
})
```

````

<img width="547" alt="Screen Shot 2021-06-02 at 11 56 48 AM" src="https://user-images.githubusercontent.com/85014/120520962-09b26c00-c39a-11eb-8084-1da710b38d7c.png">


If I add `hint = FALSE` to `fail()`, the feedback is reduced to a single code hint.

````
---
output: learnr::tutorial
runtime: shiny_prerendered
---

```{r setup, include=FALSE}
library(learnr)
library(gradethis)

gradethis_setup(
  fail.hint = TRUE,      # Give a code feedback hint on all fail*()? Remove if not desired
  fail.encourage = TRUE, # Encourage on all fail*()
  pass.praise = TRUE     # Praise on all pass*()
)
```

Type 1.


```{r yo, exercise = TRUE}

```

```{r yo-solution}
1
```

```{r yo-check}
grade_this({
  pass_if_equal()
  fail(hint = FALSE)
})
```

````

<img width="537" alt="Screen Shot 2021-06-02 at 11 57 06 AM" src="https://user-images.githubusercontent.com/85014/120520945-05864e80-c39a-11eb-8ae2-665ca943c607.png">

### Additional contract requirements

- Hint placement and precedence are also part of this behavior. With `gradethis.fail` set to `PREFACE.{maybe_code_feedback()} CONCLUSION`, `fail()` produces `PREFACE. {ex_feedback} CONCLUSION` when `gradethis.fail.hint` is either `TRUE` or `FALSE`; with global `TRUE`, `fail(hint = FALSE)` produces `PREFACE. CONCLUSION`, and `fail(hint = TRUE)` produces `PREFACE. {ex_feedback} CONCLUSION`. Here `{ex_feedback}` means the code feedback for the submitted code `2` and solution `1`. For a custom message containing `{maybe_code_feedback()}`, such as `fail("Nice try, but{maybe_code_feedback()}")`, the result is `Nice try, but {ex_feedback}` whether the hint is inherited or `hint` is set to `FALSE` or `TRUE`. For a custom message without that placeholder, `fail("Nice try!")` produces `Nice try! {ex_feedback}` when the inherited global hint is `TRUE` and `Nice try!` when it is `FALSE`; with global `TRUE`, `hint = FALSE` produces `Nice try!` and `hint = TRUE` produces `Nice try! {ex_feedback}`.
