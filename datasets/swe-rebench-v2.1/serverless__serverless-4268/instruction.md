`sls plugin install` fails
# This is a Bug Report

## Description

When installing a plugin with a command like:
`sls plugin install --name serverless-webpack`

The command fails with the error:
`Type Error: Cannot read property 'kind' of null`

## Additional Data

* ***Serverless Framework Version you're using***: 1.22
* ***Node.js Version you're using***: 8.5.0
* ***Operating System***: macos
