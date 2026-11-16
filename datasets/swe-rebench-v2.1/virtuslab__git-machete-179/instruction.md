Line numbers displayed in errors refer to non-empty lines, not all lines
.git/machete file:

```
master
  develop


  develop
```

The empty lines lead to an error in `git machete status`:

`.git/machete, line 3: branch develop re-appears in the tree definition. Edit the definition file manually with git machete edit`

while it should say:

`.git/machete, line 5: branch develop re-appears in the tree definition. Edit the definition file manually with git machete edit`

This is due to how `read_definition_file` is implemented, should be pretty easy to fix.

### Additional contract requirements

The title above describes the buggy behavior that must be fixed: currently the line number in an error is computed after empty and whitespace-only lines have been removed from the definition file, so it refers to non-empty lines rather than to all lines. After the fix, the line number reported in an error must be the physical line number within `.git/machete`, counting empty and whitespace-only lines.

For the example above, the duplicate `develop` branch is on physical line 5, so the diagnostic must report line 5. The exact diagnostic text is:

``.git/machete, line 5: branch `develop` re-appears in the tree definition. Edit the definition file manually with `git machete edit` ``

In particular, the branch name and the `git machete edit` command are each wrapped in backticks.
