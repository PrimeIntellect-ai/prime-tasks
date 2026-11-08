Creating Scratch Org fails - No authorization information found for username
### Describe the bug

Running the command `cci org info dev_namespaced` results in an error:

```
Failed to set password:

                    ERROR running force:user:password:generate:  No authorization information found for test-yfscjgi5p3kb@example.com.
```

### Reproduction steps

1. run `cci org info dev_namespaced`
2. observe cli error


### Your CumulusCI and Python versions

CumulusCI version: 3.63.0 (/Users/rf/.local/bin/cci)
Python version: 3.10.6 (/Users/rf/.local/pipx/venvs/cumulusci/bin/python)

### Operating System

MacOS

### Windows environment

_No response_

### CumulusCI installation method

pipx

### Error Gist

https://gist.github.com/ryanfollmer/b58380ff1a21bf66d7c2a433357f8ee1

### Additional information

sfdx version: sfdx-cli/7.164.2 darwin-x64 node-v16.17.0
