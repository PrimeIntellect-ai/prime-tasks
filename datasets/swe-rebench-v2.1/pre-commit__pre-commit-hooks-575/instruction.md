check-case-conflict doesn't notice directory name conflicts
```
$ git status
On branch master

Initial commit

Changes to be committed:
  (use "git rm --cached <file>..." to unstage)

    new file:   TEST/foo
    new file:   test/bar

$ git commit -m "Test"
Check for case conflicts...................................................................................Passed
[master (root-commit) 6931ba5] Test
 2 files changed, 0 insertions(+), 0 deletions(-)
 create mode 100644 TEST/foo
 create mode 100644 test/bar

$ cat .pre-commit-config.yaml
- repo: git://github.com/pre-commit/pre-commit-hooks
  sha: '0d88124ef6343fbbc6c9d2872853f73546c98a3f'
  hooks:
      - id: check-case-conflict
```

A conflict such as `Test/foo` and `test/foo` is caught though.

### Additional contract requirements

The check must reject case-insensitive conflicts in directory path components, including a newly added descendant under a directory whose name conflicts with a directory represented by tracked files, and conflicts between a directory and a file path component. It must continue to reject paths that differ only by case.
