trailing-whitespace fixer getting false positive


While bringing some Terraform files under pre-commit control, I've noticed an issue with files that do not have trailing whitespace but which are being flagged as needing fixing by the `trailing-whitespace` hook, which is causing a Travis CI build to fail unexpectedly. The files in question seem to trigger because they do not end in a newline, and I believe this to be incorrect behaviour for this hook.

Example repo: https://github.com/digirati-co-uk/pre-commit-hooks-test

This is using v1.2.1 of the pre-commit-hooks repo.

![pre-commit-hooks-test-screenshot](https://user-images.githubusercontent.com/657772/36797780-c2a0343a-1ca0-11e8-8ae3-2e3f4a53e8a0.PNG)
