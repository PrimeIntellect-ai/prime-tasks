SUSHI not reporting line number for VS filter error
The following warning does not report a line number:

> warn  The match value of filter operator "=" must be a code. For string valued properties, use the regex filter operator with a regular expression value. Support for using strings as filter values has been deprecated and will be removed in a future release.

[HIDDEN]

### Additional contract requirements

- When the warning about a string-valued value-set filter operand is emitted, the warning message must include the source file name and the line number of the filter. The message reports the file as `File: <file name>` and the line as `Line: <line number>`.
