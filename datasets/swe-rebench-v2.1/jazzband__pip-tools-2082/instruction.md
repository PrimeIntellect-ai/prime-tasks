Output --no-binary and --only-binary options to preserve pip behavior
<!-- Describe the issue briefly here. -->

#### Environment Versions

1. OS Type: Linux
1. Python version: 3.12.3
1. pip version: 24.0
1. pip-tools version: 7.4.1

#### Steps to replicate

1. Compile using `--pip-args='--only-binary=:all: --no-binary=library'
2. See that compiled requirements list the `--no-binary=library` option first, `--only-binary=:all:` option second.
3. When attempting to install from these requirements the `--no-binary` is wiped out by the `--only-binary=:all:`

#### Expected result

The resulting requirements contain `--no-binary` and `--only-binary` options that have the same behavior as input options.

#### Actual result

Requirements don't have the same behavior as input options.

This improvement matters because using --no-binary/--only-binary is the best way for users to control the amount of potential code execution that happens during the installation process. I have a local fix that I plan on creating a PR.
