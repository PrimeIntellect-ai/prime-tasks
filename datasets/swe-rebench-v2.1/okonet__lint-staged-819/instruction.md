Compatibility with core.quotepath on
I’m sharing an issue I’ve encountered recently and I hope this may help others. IMHO there’s scope for a small improvement in `lint-staged` if I’ve understood things correctly.

### Description

Every time I staged a file with a non-ascii name, I was getting error messages saying that the file that I was trying commit did not exist.

When using `eslint --fix` as the first `lint-staged` command:

```
✖ eslint found some errors. Please fix them and try committing again.
No files matching the pattern "/path/to/project/"/320/277/321/200/320/270/320/262/320/265/321/202.md"" were found.
```

When using `prettier --write` as the first `lint-staged` command:

```
✖ prettier found some errors. Please fix them and try committing again.
[error] No files matching the pattern were found: "/path/to/project/"/320/277/321/200/320/270/320/262/320/265/321/202.md"".
```

Here is my setup (nothing extraordinary):

```json
{
  "husky": {
    "hooks": {
      "pre-commit": "lint-staged",
    }
  },
  "lint-staged": {
    "**/*": [
      "eslint --fix",
      "prettier --write"
    ]
  }
}
```

As it turned out, the issue came from a git config option [`core.quotepath`](https://git-scm.com/docs/git-config#Documentation/git-config.txt-corequotePath), which turned out to be true on my machine.

### Steps to reproduce

I assume you are in a root of a git repo, in which `lint-staged` is configured similarly to above.

```sh
echo "hello world" > "привет.md"
git stage "привет.md"
```

```sh
git config core.quotepath on
git --no-pager diff --staged --name-only
# "\320\277\321\200\320\270\320\262\320\265\321\202.md"

git commit -m "Testing unicode in file names"
# ❌ because "/path/to/project/"/320/277/321/200/320/270/320/262/320/265/321/202.md"" not found
```

```sh
git config core.quotepath off
git --no-pager diff --staged --name-only
# привет.md

git commit -m "Testing unicode in file names"
# ✅ because "/path/to/project/привет.md" found
```

I managed to solve the problem locally by running `git config --global core.quotepath off` and thus avoiding `"..."` in `git ls-files`. However, other devs may fall into the same trap.

[HIDDEN]

### Environment

<!-- Tell us about your development environment -->
- **OS:** macOS 10.15.4 (19E266)
- **Node.js:** c12.15.0
- **`lint-staged`:** v10.0.9
- **`git`:** 2.26.0

### Additional contract requirements

- When Git's `core.quotepath` is enabled, `lint-staged` must correctly identify staged files with non-ASCII names and allow configured tasks to operate on those files.
