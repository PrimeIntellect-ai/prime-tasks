DOC: fix EX03 errors in docstrings
pandas has a script for validating docstrings

https://github.com/pandas-dev/pandas/blob/b7e2202459eadc9dd599cbe58251ecc930798b97/ci/code_checks.sh#L72-L172

Currently, some methods fail the EX03 check.

The task here is:
- take 2-4 methods
- run: scripts/validate_docstrings.py --format=actions --errors=EX03 `method-name`
- check if validation docstrings passes for those methods, and if it’s necessary fix the docstrings according to whatever error is reported
- remove those methods from code_checks.sh
- commit, push, open pull request

Please don't comment `take` as multiple people can work on this issue. You also don't need to ask for permission to work on this, just comment on which methods are you going to work.

If you're new contributor, please check the [contributing guide](https://pandas.pydata.org/docs/dev/development/contributing.html)

thanks @MarcoGorelli for giving me the idea for this issue.

### Additional contract requirements

- Choose 2 to 4 methods from the EX03 docstring list in `ci/code_checks.sh`.
- Run `scripts/validate_docstrings.py --format=actions --errors=EX03` on each chosen method. Its docstring must produce no EX03 errors, so correct the docstring wherever the validator reports one.
- Remove the chosen methods from the EX03 list in `ci/code_checks.sh`.
