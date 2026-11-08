Problems around parsing branch names
```
$ git machete diff develop
...
AttributeError: 'str' object has no attribute 'full_name'

$ git machete log develop
(ok)

$ git machete diff refs/heads/develop
...
TypeError: LocalBranchShortName cannot accept refs/heads or refs/remotes. Given value: refs/heads/develop.
Consider posting an issue on https://github.com/VirtusLab/git-machete/issues/new

$ git machete log refs/heads/develop
...
TypeError: LocalBranchShortName cannot accept refs/heads or refs/remotes. Given value: refs/heads/develop.
Consider posting an issue on https://github.com/VirtusLab/git-machete/issues/new
```

Hell knows what other cases result in an error... let's get this sorted and provide decent regression tests.

### Additional contract requirements

For `diff` and `log`, and analogous branch-selecting commands such as `anno`, `fork-point`, `is-managed`, and `show`, a short local branch name and its full `refs/heads/` ref must select the same local branch rather than failing during argument parsing.
