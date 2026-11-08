Running `cfn-lint file_that_does_not_exist.yml` has exit code 0 and no error message
### CloudFormation Lint Version

cfn-lint 1.19.0

### What operating system are you using?

Ubuntu

### Describe the bug

Running `cfn-lint file_that_does_not_exist.yml` should return exit_code > 0, and should ideally give a stderr message that the file doesn't exist.

Currently, the program exists the exact same way as if nothing happened.

### Expected behavior

Running `cfn-lint file_that_does_not_exist.yml` should return exit_code > 0, and should ideally give a stderr message that the file doesn't exist.

### Reproduction template

N/A
