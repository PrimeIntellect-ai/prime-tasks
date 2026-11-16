Add options to ParsePatchHeader
By default, for email formatted patches, `ParsePatchHeader` will remove all content in square brackets and place it in a separate field. This matches the default behavior of `git`, but `git` also includes flags to disable cleaning completely or to only remove content in square brackets that contains the word `PATCH`.

It should be a backwards-compatible change to have `ParsePatchHeader` accept option functions that can disable the default behavior or switch to only removing `[PATCH]` content.

### Additional contract requirements

The subject-cleaning options are selected with `WithSubjectCleanMode(m SubjectCleanMode) PatchHeaderOption`. The available modes are `SubjectCleanAll` (the default, removes reply markers and all leading bracketed subject content), `SubjectCleanPatchOnly` (removes bracketed content containing `PATCH` while retaining other bracketed content), and `SubjectCleanWhitespace` (disables reply-marker and bracketed-prefix removal). All modes trim leading and trailing whitespace; disabling prefix cleanup does not preserve surrounding whitespace. `ParsePatchHeader` must continue to work for existing callers that provide no options.
