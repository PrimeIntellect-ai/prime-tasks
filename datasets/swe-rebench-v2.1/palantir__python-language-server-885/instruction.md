It would be better to keep output from the flake8 linter to be consistent with that of pycodestyle.
Currently, the return message the flake8 linter [here](https://github.com/palantir/python-language-server/blob/develop/pyls/plugins/flake8_lint.py) does not contain the error code, while that of pycodestyle also include the error code.

It would be better to include the error code as well, something like the following:

> E303 too many blank lines (2)

It is a fairly simple fix.  Should I open a pull request for this?
