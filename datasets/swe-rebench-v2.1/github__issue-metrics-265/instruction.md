Prevent a big report to fail creating the issue
### Is your feature request related to a problem?

Issue creation API has a limit of 65536 characters. Whenever the report is longer, the action fails with the following error:

`Error: Validation Failed: {"resource":"Issue","code":"custom","field":"body","message":"body is too long (maximum is 65536 characters)"}`

This might happen easily when the amount of analyzed PRs is over ~300.

### Describe the solution you'd like

I would like the action to validate the size of the report before submission, splitting the extra details into multiple comments if necessary (or just create the issue with whatever it fits) without failure.

### Describe alternatives you've considered

Alternatively, the action could support a config flag to include in the report only the first two tables with the basic stats, so all the details of each single PR are not reported.

### Additional context

Thanks!

### Additional contract requirements

- Add a public function `markdown_too_large_for_issue_body(file_path: str, max_char_count: int) -> bool` in the `markdown_helpers` module. It returns `True` when the contents of the file at `file_path` exceed `max_char_count` characters, and `False` otherwise.
- Add a public function `split_markdown_file(file_path: str, max_char_count: int) -> None` in the `markdown_helpers` module. It partitions the contents of the file at `file_path` into a series of new markdown files named `<original_name>_0.md`, `<original_name>_1.md`, and so on, each containing at most `max_char_count` characters, and together containing the original content.
- The action writes its report to `issue_metrics.md`. When that report exceeds the issue body character limit, the action must not leave an oversized `issue_metrics.md` for issue creation.
