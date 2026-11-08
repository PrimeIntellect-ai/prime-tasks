`awesome/github` reports incorrectly for URL shorthands
Hello fine folks! 👋

## Problem

I get a message saying `Repository should be on GitHub` ([from here](https://github.com/sindresorhus/awesome-lint/blob/0aafda85989e32f6e2996ffd5947429cb893331b/rules/github.js#L11-L22)) because awesome-lint incorrectly reports my remote URL as not being on GitHub.

The reason for that is that `git config --get remote.origin.url` yields `gh:remarkjs/awesome-remark`.

This is indeed not a valid GitHub URL, but Git supports URL shorthands. I have the following in my Git config (`~/.gitconfig`):

```
[url "git@github.com:"]

	insteadOf = "gh:"
	pushInsteadOf = "github:"
	pushInsteadOf = "git://github.com/"
```

The reason I do this is that it makes it easy to clone from GH: `git clone gh:remarkjs/awesome-remark`.
I don’t know how many people use Git URL shorthands. But this pattern is from [`mathiasbynens/dotfiles`](https://github.com/mathiasbynens/dotfiles) so I’m guessing it’s pretty common.

## Solution

[HIDDEN]

### Additional contract requirements

- When a remote configured with a Git URL shorthand resolves to a GitHub URL, the `github` rule must recognize it as a GitHub repository rather than report that it is not on GitHub.
