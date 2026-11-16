Fix zip and other cases of simultaneous iteration
`zip` is used in array equality, and breaks chunking order when arrays with different chunks are used.

We should at minimum fix it so that the chunks of the first disk array found are used for all others (and for regular arrays). [HIDDEN] It may be slow in some cases but will at least be correct.

Later we could optimise the combined iteration pattern of all diskarrays passed to `zip`.
