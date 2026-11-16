Packaging functions individually causes "no serviceName.zip file found in the package path you provided"
<!--
1. If you have a question and not a bug report please ask first at http://forum.serverless.com
2. Please check if an issue already exists. This bug may have already been documented
3. Check out and follow our Guidelines: https://github.com/serverless/serverless/blob/master/CONTRIBUTING.md
4. Fill out the whole template so we have a good overview on the issue
5. Do not remove any section of the template. If something is not applicable leave it empty but leave it in the Issue
6. Please follow the template, otherwise we'll have to ask you to update it
-->

# This is a Bug Report

## Description

`sls deploy` fails when packaging functions individually, but succeeds when not packaging functions individually (increasing package size and adding unnecessary files to Lambda function).

* What went wrong?
`sls deploy` fails when packaging functions individually.
* What did you expect should have happened?
`sls deploy` should deploy with individually packaged functions.
* What was the config you used?
```yaml
service: serviceName

provider:
  name: aws
  runtime: python3.7
  stage: ${opt:stage, 'dev'}
  iamRoleStatements:
    [redacted]
  versionFunctions: false
  package:
    individually: true
  environment:
    [redacted]

functions:
  function0:
    handler: src/handlers/function0.main
    name: ${opt:stage, self:provider.stage}-${self:service}-function0
    package:
      individually: true
      exclude:
        - "./**"
      include:
        - src/handlers/function0.py
        - README.md
    environment:
      [redacted]
    events:
      [redacted]
  function1:
    handler: src/handlers/function1.main
    name: ${opt:stage, self:provider.stage}-${self:service}-function1
    package:
      individually: true
      exclude:
        - "**/*"
      include:
        - src/handlers/function1.py
        - README.md
    environment:
      [redacted]
  function2:
    handler: src/handlers/function2.main
    name: ${opt:stage, self:provider.stage}-${self:service}-function2
    package:
      individually: true
      exclude:
        - "**/*"
      include:
        - src/handlers/function2.py
        - README.md
    environment:
      [redacted]
  function3:
    handler: src/handlers/function3.main
    name: ${opt:stage, self:provider.stage}-${self:service}-function3
    package:
      individually: true
      exclude:
        - "**/*"
      include:
        - src/handlers/function3.py
        - README.md
    environment:
      [redacted]
  function4:
    handler: src/handlers/function4.main
    name: ${opt:stage, self:provider.stage}-${self:service}-function4
    package:
      individually: true
      exclude:
        - "**/*"
      include:
        - src/handlers/function4.py
        - README.md
    environment:
      [redacted]
  function5:
    handler: src/handlers/function5.main
    name: ${opt:stage, self:provider.stage}-${self:service}-function5
    package:
      individually: true
      exclude:
        - "**/*"
      include:
        - src/handlers/function5.py
        - README.md
    environment:
      [redacted]
  function6:
    handler: src/handlers/function6.main
    name: ${opt:stage, self:provider.stage}-${self:service}-function6
    package:
      individually: true
      exclude:
        - "**/*"
      include:
        - src/handlers/function6.py
        - README.md
    environment:
      [redacted]

stepFunctions:
  stateMachines:
    stateMachine:
      name: ${opt:stage, self:provider.stage}-${self:service}
      definition:
        [redacted]

plugins:
  - serverless-offline
  - serverless-offline-scheduler
  - serverless-pseudo-parameters
  - serverless-step-functions
  - serverless-dotenv-plugin

```
* What stacktrace or error message from your provider did you see?
```
$ sls deploy
Serverless: DOTENV: Loading environment variables from .env:
[redacted]
Serverless: Packaging service...
Serverless: Excluding development dependencies...
Serverless: Excluding development dependencies...
Serverless: Excluding development dependencies...
Serverless: Excluding development dependencies...
Serverless: Excluding development dependencies...
Serverless: Excluding development dependencies...
Serverless: Excluding development dependencies...

  Serverless Error ---------------------------------------

  No serviceName.zip file found in the package path you provided.

  Get Support --------------------------------------------
     Docs:          docs.serverless.com
     Bugs:          github.com/serverless/serverless/issues
     Issues:        forum.serverless.com

  Your Environment Information ---------------------------
     OS:                     linux
     Node Version:           8.10.0
     Serverless Version:     1.42.2
 ```
Similar or dependent issues:
* #4720
* #5929
* #5931

## Additional Data

* ***Serverless Framework Version you're using***:
```
  Your Environment Information ---------------------------
     OS:                     linux
     Node Version:           8.10.0
     Serverless Version:     1.42.2
```
* ***Operating System***:
```
$ uname -a
Linux ip-[redacted] 4.14.97-74.72.amzn1.x86_64 #1 SMP Tue Feb 5 20:59:30 UTC 2019 x86_64 x86_64 x86_64 GNU/Linux
```
* ***Stack Trace***: N/A
* ***Provider Error messages***: N/A

### Additional contract requirements

- `sls deploy` must complete its packaging and validation phase successfully (for example when invoked as `sls deploy --noDeploy`) when functions declare `package.individually: true` at the function level, even if the service-level `package.individually` is not set.
- When a function is packaged individually, its artifact is written to `.serverless/<functionName>.zip` and contains exactly the files selected by that function's `package.include` and `package.exclude` patterns.
