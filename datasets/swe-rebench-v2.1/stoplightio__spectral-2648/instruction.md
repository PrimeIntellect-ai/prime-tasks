Gitlab code quality support
**User story.**
As a developer, I can export the results to a Gitlab code quality report to see a summary of my code quality in the MR widget and the pipeline.

**Is your feature request related to a problem?**
Currently, there is only a format enum for JUnit. That's cool because you can see the results in Gitlab, but I prefer linting results in the code quality section. The linting results are more about the quality, not in all cases about functionality.

**Describe the solution you'd like**
It would be cool to have another output format in the CodeClimate JSON format.

### Additional contract requirements

- Add a public formatter function `codeClimate(results, options?)` in `packages/formatters/src/code-climate.ts`, where `options` may include `failSeverity`. It returns a `string` containing JSON that represents an array with one Code Climate issue object per result. Each issue includes a `description` and a `location` with a relative file `path` and `positions` giving the begin and end line and column.
- The CLI supports `gitlab` and `code-climate` as output format values, both producing the Code Climate JSON report.
- Each issue follows the Code Climate issue schema, including the required `type`, `check_name`, `categories`, and `fingerprint` fields.
