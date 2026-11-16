On-the-fly linters should respect project lint settings
This breaks because the editor typically copies the source file being linted to a temporary directory, so lintr cannot find any config files.  Either have to
- Force the editors not to use temp files (not ideal)
- Pass the true filename to lintr as well
- Read the config separately and pass the options found to the lint process.

### Additional contract requirements

- `lint()` must accept source code through a public `text` argument, as a single string or a vector of lines, without requiring a readable source file.
- When linting supplied text, an optional `filename` identifies the original source path for discovering and applying project lint settings; the file itself need not exist. If no filename is supplied, the text can still be linted.
