Branch not deleted when checked out
**Describe the bug**
To Reproduce:
1. Create any PR
2. Squash and merge PR
3. `gh poi`
4. Can't delete PR branch in local

**Your Environment**
- OS: macOS Monterey
- gh (Check with `gh --version`): 2.14.4
- gh-poi (For gh v2.6+ check with `gh extension list`): v0.6.2

### Additional contract requirements

- A branch associated with a merged pull request that is currently checked out must be deletable when the only uncommitted changes in the working tree are untracked files.
- A branch associated with a merged pull request that is currently checked out must not be deletable while the working tree contains tracked uncommitted changes (modified or staged files).
