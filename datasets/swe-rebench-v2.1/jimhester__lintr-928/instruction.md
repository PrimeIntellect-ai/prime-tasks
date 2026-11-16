Cover other assignment operators in assignment_linter
Follow-up to

https://github.com/AshesITR/lintr/pull/1#discussion_r820137490

I think `->` should be covered by assignment_linter, and we can include an option for whether to cover `<<-` and `->>` as well

### Additional contract requirements

`assignment_linter()` accepts the logical options `allow_cascading_assign` (default `TRUE`) and `allow_right_assign` (default `FALSE`). With `allow_cascading_assign = FALSE`, uses of `<<-` and `->>` produce lints. With `allow_right_assign = TRUE` and cascading assignments allowed, neither `->` nor `->>` is linted; when cascading assignments are disallowed, `->>` remains linted. The default configuration reports `->` assignments.
