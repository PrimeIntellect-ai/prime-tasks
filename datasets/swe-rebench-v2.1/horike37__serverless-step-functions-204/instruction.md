Template error: every value of the context object of every Fn::Sub object must be a string or a function that returns a string
# This is a Bug Report

## Description

Recently we upgraded version from v1.17.1 to v1.20, and we started getting following error:
```
╰─ sls deploy -s dev -r us-west-2
Serverless: Generated requirements from /abc/requirements.txt in /abc/.serverless/requirements.txt...
Serverless: Installing requirements from /abc/.serverless/requirements/requirements.txt ...
Serverless: Running ...
Serverless: Packaging service...
Serverless: Excluding development dependencies...
Serverless: Injecting required Python packages to package...
Serverless: Uploading CloudFormation file to S3...
Serverless: Uploading artifacts...
Serverless: Uploading service abc.zip file to S3 (10.76 MB)...
Serverless: Validating template...

  Error --------------------------------------------------

  The CloudFormation template is invalid: Template error: every value of the context object of every Fn::Sub object must be a string or a function that returns a string

     For debugging logs, run again after setting the "SLS_DEBUG=*" environment variable.

  Get Support --------------------------------------------
     Docs:          docs.serverless.com
     Bugs:          github.com/serverless/serverless/issues
     Issues:        forum.serverless.com

  Your Environment Information ---------------------------
     OS:                     darwin
     Node Version:           12.3.1
     Serverless Version:     1.40.0
```

For bug reports:
* What went wrong? Serverless failed to verify cloudformation template
* What did you expect should have happened? Serverless shpuld to verify cloudformation template


## Additional Data
* ***Serverless Framework Core Version you're using***: 1.40.0
* ***The Plugin Version you're using***: 1.20.0
* ***Operating System***: MacOS 10.14.5

### Additional contract requirements

- State names beginning with `Ref` must be treated as state names, not as intrinsic functions. When compiling a definition containing the states `One`, `RefreshLead`, and `EndState`, `Properties.DefinitionString` must not have its own `Fn::Sub` property, and the parsed definition’s `States` object must contain all three names.
