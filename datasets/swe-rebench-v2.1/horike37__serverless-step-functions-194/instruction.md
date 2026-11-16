Serverless deploy failing when using null values on 1.18.0
# This is a (Bug Report / Feature Proposal)

## Description

For bug reports:
* What went wrong? Serverless deploy failing when using null value in ResultPath
* What did you expect should have happened? Serverless deploy succeeds
* What was the config you used?
* What stacktrace or error message from your provider did you see? See below

For feature proposals:
* What is the use case that should be solved. The more detail you describe this in the easier it is to understand for us.
* If there is additional config how would it look

It works fine for 1.17.1 and previous versions

Similar or dependent issues:
* #12345

## Additional Data
* ***Serverless Framework Core Version you're using***: 1.41.1
* ***The Plugin Version you're using***: 1.18.0
* ***Operating System***: Ubuntu 14.04
* ***Stack Trace***:

Serverless: Load command config
Serverless: Load command config:credentials
Serverless: Load command create
Serverless: Load command install
Serverless: Load command package
Serverless: Load command deploy
Serverless: Load command deploy:function
Serverless: Load command deploy:list
Serverless: Load command deploy:list:functions
Serverless: Load command invoke
Serverless: Load command invoke:local
Serverless: Load command info
Serverless: Load command logs
Serverless: Load command metrics
Serverless: Load command print
Serverless: Load command remove
Serverless: Load command rollback
Serverless: Load command rollback:function
Serverless: Load command slstats
Serverless: Load command plugin
Serverless: Load command plugin
Serverless: Load command plugin:install
Serverless: Load command plugin
Serverless: Load command plugin:uninstall
Serverless: Load command plugin
Serverless: Load command plugin:list
Serverless: Load command plugin
Serverless: Load command plugin:search
Serverless: Load command config
Serverless: Load command config:credentials
Serverless: Load command rollback
Serverless: Load command rollback:function
Serverless: Load command requirements
Serverless: Load command requirements:clean
Serverless: Load command requirements:install
Serverless: Load command requirements:cleanCache
Serverless: Load command invoke
Serverless: Load command invoke:stepf
Serverless: Invoke deploy
Serverless: Invoke package
Serverless: Invoke aws:common:validate
Serverless: Invoke aws:common:cleanupTempDir
Serverless: Generated requirements from /codebuild/output/src449281441/src/requirements.txt in /codebuild/output/src449281441/src/.serverless/requirements.txt...
Serverless: Installing requirements from /codebuild/output/src449281441/src/.serverless/requirements/requirements.txt ...
Serverless: Running ...
Serverless: Packaging service...
Serverless: Excluding development dependencies...
Serverless: Injecting required Python packages to package...

  Type Error ---------------------------------------------

  Cannot convert undefined or null to object

     For debugging logs, run again after setting the "SLS_DEBUG=*" environment variable.

  Stack Trace --------------------------------------------

TypeError: Cannot convert undefined or null to object
    [HIDDEN]
    at getIntrinsicFunctions (/codebuild/output/src449281441/src/node_modules/serverless-step-functions/lib/deploy/stepFunctions/compileStateMachines.js:49:18)
    at getIntrinsicFunctions.next (<anonymous>)
    at Function.from (<anonymous>)
    at getIntrinsicFunctions (/codebuild/output/src449281441/src/node_modules/serverless-step-functions/lib/deploy/stepFunctions/compileStateMachines.js:55:34)
    at getIntrinsicFunctions.next (<anonymous>)
    at Function.from (<anonymous>)
    at getIntrinsicFunctions (/codebuild/output/src449281441/src/node_modules/serverless-step-functions/lib/deploy/stepFunctions/compileStateMachines.js:55:34)
    at getIntrinsicFunctions.next (<anonymous>)
    at Function.from (<anonymous>)
    at /codebuild/output/src449281441/src/node_modules/serverless-step-functions/lib/deploy/stepFunctions/compileStateMachines.js:79:44
    at Array.forEach (<anonymous>)
    at ServerlessStepFunctions.compileStateMachines (/codebuild/output/src449281441/src/node_modules/serverless-step-functions/lib/deploy/stepFunctions/compileStateMachines.js:67:34)
From previous event:
    at PluginManager.invoke (/usr/local/lib/node_modules/serverless/lib/classes/PluginManager.js:408:22)
    at PluginManager.spawn (/usr/local/lib/node_modules/serverless/lib/classes/PluginManager.js:426:17)
    at Deploy.<anonymous> (/usr/local/lib/node_modules/serverless/lib/plugins/deploy/deploy.js:122:50)
From previous event:
    at Object.before:deploy:deploy [as hook] (/usr/local/lib/node_modules/serverless/lib/plugins/deploy/deploy.js:107:10)
    at /usr/local/lib/node_modules/serverless/lib/classes/PluginManager.js:408:55
From previous event:
    at PluginManager.invoke (/usr/local/lib/node_modules/serverless/lib/classes/PluginManager.js:408:22)
    at PluginManager.run (/usr/local/lib/node_modules/serverless/lib/classes/PluginManager.js:439:17)
    at /usr/local/lib/node_modules/serverless/lib/Serverless.js:109:33
    at processImmediate (internal/timers.js:439:21)
    at process.topLevelDomainCallback (domain.js:126:23)
From previous event:
    at Serverless.run (/usr/local/lib/node_modules/serverless/lib/Serverless.js:96:6)
    at /usr/local/lib/node_modules/serverless/bin/serverless:43:28
    at /usr/local/lib/node_modules/serverless/node_modules/graceful-fs/graceful-fs.js:111:16
    at /usr/local/lib/node_modules/serverless/node_modules/graceful-fs/graceful-fs.js:45:10
    at FSReqCallback.oncomplete (fs.js:153:20)
From previous event:
    at /usr/local/lib/node_modules/serverless/bin/serverless:43:6
    at processImmediate (internal/timers.js:439:21)
    at process.topLevelDomainCallback (domain.js:126:23)
From previous event:
    at /usr/local/lib/node_modules/serverless/bin/serverless:28:46
    at Object.<anonymous> (/usr/local/lib/node_modules/serverless/bin/serverless:65:4)
    at Module._compile (internal/modules/cjs/loader.js:759:30)
    at Object.Module._extensions..js (internal/modules/cjs/loader.js:770:10)
    at Module.load (internal/modules/cjs/loader.js:628:32)
    at Function.Module._load (internal/modules/cjs/loader.js:555:12)
    at Function.Module.runMain (internal/modules/cjs/loader.js:824:10)
    at internal/main/run_main_module.js:17:11

  Get Support --------------------------------------------
     Docs:          docs.serverless.com
     Bugs:          github.com/serverless/serverless/issues
     Issues:        forum.serverless.com

  Your Environment Information ---------------------------
     OS:                     linux
     Node Version:           12.1.0
     Serverless Version:     1.41.1


* ***Provider Error messages***:

### Additional contract requirements

- A state-machine definition containing `ResultPath: null` must compile successfully, and the resulting deployable definition must preserve that `null` value.
