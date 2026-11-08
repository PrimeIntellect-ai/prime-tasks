Implement a boolean flag --fails-only to print only licenses found for --fail flags

### Additional contract requirements

- The flag is spelled `--fails-only` and is a boolean flag.
- The parsed command-line options expose the flag as the boolean key `:fails-only`, which is `false` when the flag is not given and `true` when it is.
- When `:fails-only` is true and the `:fail` set is non-empty, only the licenses whose license type is in the `:fail` set are printed; when `:fails-only` is false or the `:fail` set is empty, all licenses are printed.
- The licenses to be filtered may be supplied as a sequence, a vector, or `nil`.
