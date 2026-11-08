Validation of edifact fails when an empty segment starts a loop in an implementation schema
If the empty segment is removed (from schemas and edifact file), the validation works perfectly. Same if the empty segment is moved to second or following positions in the loop.

A failed test is attached.

[empty-segment-loop-validation.zip](https://github.com/xlate/staedi/files/5033161/empty-segment-loop-validation.zip)
