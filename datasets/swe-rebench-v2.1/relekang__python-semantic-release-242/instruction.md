Option to show changelog as a table
## Description

Add an option to display the changelog in table format, rather than using headings.

![image](https://user-images.githubusercontent.com/28959268/81698565-1944d700-945e-11ea-95e1-119a1a6a1d3f.png)

## Use cases

- Could look nice with [emojis](https://github.com/relekang/python-semantic-release/pull/238) as type of change
- The list is more compact, which is good for releasing many commits at once - e.g. on a weekly cron

## Possible implementation

- Insert a fixed header of:
  ```
  | Type | Change |
  |------|--------|
  ```
- Each section is of the format:
  ```
  | <heading text> | <commits> |
  ```
- Use `<br>` to get a new line between commits
- However, lists cannot be used in a table

### Additional contract requirements

- Add a public function `changelog_table(changelog: dict, changelog_sections: list, **kwargs) -> str` in the module `semantic_release.changelog.changelog`.
- `changelog` maps change-type keys to a list of `(commit_message, commit_sha)` tuples, both strings.
- The returned value is a Markdown table whose first line is exactly `| Type | Change |`, followed by a separator line.
- Each rendered section containing commits produces a row of the form `| <Section Title> | <commit message> (<sha>)<br>... |`, where `<Section Title>` is the section name with its first character upper-cased and multiple commits are joined with `<br>`.
- Keyword arguments are accepted and do not change the returned value.
