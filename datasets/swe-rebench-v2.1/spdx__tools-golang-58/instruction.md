Fix multiline snippet copyright in tvsaver
Currently, in tvsaver, Snippet copyright text lines are [HIDDEN]: https://github.com/spdx/tools-golang/blob/feb87345dfd6d6f76a9b1fc2ef413a2e8a756be8/tvsaver/saver2v1/save_snippet.go#L36

(compare, for Files, https://github.com/spdx/tools-golang/blob/feb87345dfd6d6f76a9b1fc2ef413a2e8a756be8/tvsaver/saver2v1/save_file.go#L42 and corresponding test at https://github.com/spdx/tools-golang/blob/feb87345dfd6d6f76a9b1fc2ef413a2e8a756be8/tvsaver/saver2v1/save_file_test.go#L213)

[HIDDEN]

### Additional contract requirements

- For SPDX 2.1 and 2.2, multiline snippet copyright text must be rendered using the same wrapping convention as multiline file copyright text.
