Blob link breaks if keyword is at end of file
Currently, if the issue-to-be is at the end of a file, the blob link will break because there is no line `start + 5`. This came up in #38.

### Additional contract requirements

- The blob link must point at the line that contains the keyword and the issue title. Keyword matching is case-insensitive by default (the `caseSensitive` option defaults to `false`), so a line such as `@TODO My title` must be located when the configured keyword is `@todo`.


- When the configured blob range extends past the end of the file, the link must end at the file's last existing line; for example, a match on line 9 of a 10-line file must produce the fragment `#L9-L10`.
