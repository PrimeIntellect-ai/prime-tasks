Bug: SSM variable syntax fails to retrieve parameters with a dash in the name
<!--
1. If you have a question and not a bug/feature request please ask it at http://forum.serverless.com
2. Please check if an issue already exists so there are no duplicates
3. Check out and follow our Guidelines: https://github.com/serverless/serverless/blob/master/CONTRIBUTING.md
4. Fill out the whole template so we have a good overview on the issue
5. Do not remove any section of the template. If something is not applicable leave it empty but leave it in the Issue
6. Please follow the template, otherwise we'll have to ask you to update it
-->

# This is a Bug Report

## Description

When using the SSM variable syntax, serverless fails to retrieve the value when the parameter name includes a dash (`-`). The warning below is generated:

```
Serverless Warning --------------------------------------

 A valid SSM parameter to satisfy the declaration 'ssm:/foo/foo-bar/param' could not be found.
```

A dash is a valid character for an SSM parameter name, so serverless should lookup and return the value.

## Additional Data

* ***Serverless Framework Version you're using***: 1.21.1
* ***Operating System***: Win10
