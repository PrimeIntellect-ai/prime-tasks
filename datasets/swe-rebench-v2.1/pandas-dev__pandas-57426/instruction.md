DOC: fix SA05 errors in docstrings
Pandas has a script for validating docstrings:

https://github.com/pandas-dev/pandas/blob/1d7aedcd19470f689e4db625271802eb49531e80/ci/code_checks.sh#L145-L206

Currently, some methods fail the SA05 check.

The task here is:

- take 2-4 methods
- run: scripts/validate_docstrings.py --format=actions --errors=SA05 `method-name`
- check if validation docstrings passes for those methods, and if it’s necessary fix the docstrings according to whatever error is reported
- remove those methods from code_checks.sh
- commit, push, open pull request
- Please don't comment `take` as multiple people can work on this issue. You also don't need to ask for permission to work on this, just comment on which methods are you going to work.

If you're new contributor, please check the [contributing guide](https://pandas.pydata.org/docs/dev/development/contributing.html)
