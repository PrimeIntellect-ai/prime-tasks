Cannot read property 'events' of undefined

# This is a Bug Report

## Description

* What went wrong?
An error when deploying a package. The service is deployed correctly but the Package plugin is throwing an error at the end. If deploying without packaging it first, no errors are thrown but I want to package first so I can have different stages in my CI.

    Commands run:
    * `sls package -p package`
    * `sls deploy --package package`

* What did you expect should have happened?
No errors

* What was the config you used?
```
provider:
  name: aws
  runtime: python3.6
  stage: ${opt:stage, "dev"}

  region: us-east-1
  iamManagedPolicies:
    - "arn:aws:iam::aws:policy/AmazonCognitoPowerUser"
    - "arn:aws:iam::aws:policy/AmazonS3FullAccess"
    - "arn:aws:iam::aws:policy/SecretsManagerReadWrite"

package:
  exclude:
  - node_modules/**
  - .idea/**
  - __pycache__/**
  - package.json
  - package-lock.json
  - sls_hooks/**
  - Pipfile
  - resource/**

functions:
  postSignUp:
    handler: cognito/postSignupConfirmation.handler
    events:
    - cognitoUserPool:
        pool: myUserPool
        trigger: PostConfirmation

  graphql:
    handler: graphql_api.handler
    runtime: python3.6

  download:
    handler: api_gateway/download.handler
    runtime: python3.6
    events:
      - http:
          path: download
          method: get

```

* What stacktrace or error message from your provider did you see?
```
  Stack Trace --------------------------------------------

TypeError: Cannot read property 'events' of undefined
    at Object.after:deploy:deploy [as hook] (/codebuild/output/src613376632/src/backend/node_modules/serverless/lib/plugins/aws/package/compile/events/apiGateway/index.js:77:28)
    at BbPromise.reduce (/codebuild/output/src613376632/src/backend/node_modules/serverless/lib/classes/PluginManager.js:422:55)
From previous event:
    at PluginManager.invoke (/codebuild/output/src613376632/src/backend/node_modules/serverless/lib/classes/PluginManager.js:422:22)
    at PluginManager.run (/codebuild/output/src613376632/src/backend/node_modules/serverless/lib/classes/PluginManager.js:453:17)
    at variables.populateService.then (/codebuild/output/src613376632/src/backend/node_modules/serverless/lib/Serverless.js:109:33)
    at runCallback (timers.js:705:18)
    at tryOnImmediate (timers.js:676:5)
    at processImmediate (timers.js:658:5)
    at process.topLevelDomainCallback (domain.js:120:23)
From previous event:
    at Serverless.run (/codebuild/output/src613376632/src/backend/node_modules/serverless/lib/Serverless.js:96:6)
    at serverless.init.then (/codebuild/output/src613376632/src/backend/node_modules/serverless/bin/serverless:43:28)
    at /codebuild/output/src613376632/src/backend/node_modules/graceful-fs/graceful-fs.js:111:16
    at /codebuild/output/src613376632/src/backend/node_modules/graceful-fs/graceful-fs.js:45:10
    at FSReqWrap.args [as oncomplete] (fs.js:140:20)
From previous event:
    at initializeErrorReporter.then (/codebuild/output/src613376632/src/backend/node_modules/serverless/bin/serverless:43:6)
    at runCallback (timers.js:705:18)
    at tryOnImmediate (timers.js:676:5)
    at processImmediate (timers.js:658:5)
    at process.topLevelDomainCallback (domain.js:120:23)
From previous event:
    at /codebuild/output/src613376632/src/backend/node_modules/serverless/bin/serverless:28:46
    at Object.<anonymous> (/codebuild/output/src613376632/src/backend/node_modules/serverless/bin/serverless:65:4)
    at Module._compile (internal/modules/cjs/loader.js:701:30)
    at Object.Module._extensions..js (internal/modules/cjs/loader.js:712:10)
    at Module.load (internal/modules/cjs/loader.js:600:32)
    at tryModuleLoad (internal/modules/cjs/loader.js:539:12)
    at Function.Module._load (internal/modules/cjs/loader.js:531:3)
    at Function.Module.runMain (internal/modules/cjs/loader.js:754:12)
    at findNodeScript.then.existing (/usr/local/lib/node_modules/npm/node_modules/libnpx/index.js:268:14)
```

Similar or dependent issues:
None that I know of

## Additional Data

* ***Serverless Framework Version you're using***: 1.42.1
* ***Operating System***: Amazon Linux but also happens locally in my Macbook OS X
* ***Stack Trace***:
* ***Provider Error messages***:

### Additional contract requirements

The sequence `sls package -p package` followed by `sls deploy --package package` must complete without an error when the deploy step uses the package, even if the current service configuration omits functions included in the package. The deployment must tolerate packaged functions with non-HTTP events and packaged functions with no events.
