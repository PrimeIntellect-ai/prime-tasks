fix categorized flags alongside non categorized
## My urfave/cli version is

latest v2

## Checklist

- [X] Are you running the latest v2 release? The list of releases is [here](https://github.com/urfave/cli/releases).
- [X] Did you check the manual for your release? The v2 manual is [here](https://github.com/urfave/cli/blob/main/docs/v2/manual.md)
- [X] Did you perform a search about this problem? Here's the [GitHub guide](https://help.github.com/en/github/managing-your-work-on-github/using-search-to-filter-issues-and-pull-requests) about searching.

## Describe the bug

Commit: https://github.com/urfave/cli/commit/8227be1fe9df91e3d69e17514df21b8e609d6cd0
introduced a backward compatibility issue.  As before non categorized flags would show alongside categorized flags.  After this commit non categorized do not show at all.


## To reproduce

TestCommand_VisibleFlagCategories is a direct test of the breaking change, Just because no category is set, the flag should not be invisible.

## Expected behavior

Flags should show in help unless explicitly hidden

## Want to fix this yourself?

Sure, I'll introduce a PR shortly

## Run `go version` and paste its output here

```
go version go1.19.4 linux/amd64
```
