Change scope with commit_parsers
**Is your feature request related to a problem? Please describe.**
In a monorepo, I that have a folder with the name "www", however, since I am using git-cliff to generate a public-facing, I would wish for this to be displayed as "Application" when generated.

I am using template replace functions to replace "www" with "Application" but would like the ability to change this in the `commit_parsers`.

**Describe the solution you'd like**
`commit_parsers` should allow changing of the scope on-demand. For example:

```toml
commit_parsers = [
  { message = "(www)", scope = "Application" }
]
```

**Describe alternatives you've considered**
N/A

**Additional context**
Thanks for an awesome project!

### Additional contract requirements

A scope specified by a matching `commit_parsers` entry replaces any scope already present in the conventional commit message when the commit is displayed in the generated changelog.
