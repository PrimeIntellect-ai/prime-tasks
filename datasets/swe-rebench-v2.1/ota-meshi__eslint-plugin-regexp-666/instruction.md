Add suggestions for `no-useless-assertion`
**Description**
Since we know when an assertion always accepts/rejects, we can add a suggestion that removes the asserion/the branch of the assertion.

E.g. `/a\Bb/` -> `/ab/` and `/a|$b/` -> `/a/`

### Additional contract requirements

- Use the message ID `acceptSuggestion` for suggestions that remove an always-accepting assertion, and `rejectSuggestion` for suggestions that remove a rejecting branch.
- A rejecting assertion that is quantified with a minimum of 0 is removed together with its quantifier.
- Otherwise, a suggestion that removes a rejecting branch replaces the branch with the empty set `[]` when the branch is the only alternative of its pattern or of a capturing group, and removes the branch when it is not.
