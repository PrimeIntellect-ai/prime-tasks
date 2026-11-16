New assertion: `containsMatch`
A mixture of `contains` and `match`, but only looks for a match within the string rather than against the whole thing.

Implementation is basically `[HIDDEN]`, but it's nice to not have to do that every time you want to switch from an exact `contains` to a fuzzy, regex-based one (or similarly, from matching the whole string to only part of a string).
