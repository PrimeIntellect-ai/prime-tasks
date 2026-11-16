`insert_final_newline` should ensure a single newline character at the end of the file
Right now, editorconfig-checker does not complain about multiple newlines at EOF when the `insert_final_newline` option is set.

According to [this comment](https://github.com/editorconfig/editorconfig/issues/483#issuecomment-1451447540) on a feature request to support specifying the number of newlines that should be at EOF the option is intended to mean that a file should end in a singular newline, so editorconfig-checker should complain about multiple newlines at the end of a file.
