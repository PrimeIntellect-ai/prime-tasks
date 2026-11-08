Add option to force git checkouts
I see from the `--diff-git-checkouts` option description that inability to do `git checkout` on a dirty tree is a feature. However, there are cases where it's not desirable. In our case rust build script produces some artefacts that are supposed to be checked in the repo. So, when the tool checks out the first commit and generates the docs the tree is not clean and the tools fails to checkout the second commit.

Would you accept a PR implementing an additional `--force-git-checkouts` option?

### Additional contract requirements

- Provide a `--force-git-checkouts` command-line option.
- When used together with `--diff-git-checkouts`, this option allows switching to the commits being diffed even if the working tree has local changes that would otherwise block checkout.
- Without `--force-git-checkouts`, diffing must continue to refuse a checkout that would overwrite local changes.
