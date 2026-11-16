Error with multiple runtimes
<!--
1. Please check if an issue already exists so there are no duplicates
2. Fill out the whole template so we have a good overview on the issue
3. Do not remove any section of the template. If something is not applicable leave it empty but leave it in the Issue
4. Please follow the template, otherwise we'll have to ask you to update it
-->

# This is a Bug Report

## Description

If you try to add a second runtime (in my example golang) for a new Lambda, you get following error:
TypeError [ERR_INVALID_ARG_TYPE]: The "to" argument must be of type string. Received undefined
in
node_modules/serverless-webpack/lib/validate.js:199:36
because the plugin tries to use the golang lambda to do webpack stuff.

[HIDDEN]

## Additional Data

* ***Serverless-Webpack Version you're using***: 5.3.5
* ***Webpack version you're using***: 4.44.2
* ***Serverless Framework Version you're using***: 2.4.0
* ***Operating System***: Windows 10 WSL, so I guess linux?
* ***Stack Trace (if available)***:
 Type Error ---------------------------------------------

  TypeError [ERR_INVALID_ARG_TYPE]: The "to" argument must be of type string. Received undefined
      at validateString (internal/validators.js:120:11)
      at Object.relative (path.js:1054:5)
      at /home/dennis/go/src/sportsplaner/node_modules/serverless-webpack/lib/validate.js:199:36
      at arrayMap (/home/dennis/go/src/sportsplaner/node_modules/lodash/lodash.js:639:23)
      at Function.map (/home/dennis/go/src/sportsplaner/node_modules/lodash/lodash.js:9580:14)
      at processConfig (/home/dennis/go/src/sportsplaner/node_modules/serverless-webpack/lib/validate.js:196:37)
      at ServerlessWebpack.validate (/home/dennis/go/src/sportsplaner/node_modules/serverless-webpack/lib/validate.js:245:14)
  From previous event:
      at Object.webpack:validate:validate [as hook] (/home/dennis/go/src/sportsplaner/node_modules/serverless-webpack/index.js:152:63)
      at /home/dennis/go/src/sportsplaner/node_modules/serverless/lib/classes/PluginManager.js:510:55
  From previous event:
      at PluginManager.invoke (/home/dennis/go/src/sportsplaner/node_modules/serverless/lib/classes/PluginManager.js:510:22)
      at PluginManager.spawn (/home/dennis/go/src/sportsplaner/node_modules/serverless/lib/classes/PluginManager.js:530:17)
      at ServerlessWebpack.<anonymous> (/home/dennis/go/src/sportsplaner/node_modules/serverless-webpack/index.js:93:53)
  From previous event:
      at Object.before:package:createDeploymentArtifacts [as hook] (/home/dennis/go/src/sportsplaner/node_modules/serverless-webpack/index.js:93:12)
  From previous event:
      at PluginManager.invoke (/home/dennis/go/src/sportsplaner/node_modules/serverless/lib/classes/PluginManager.js:510:22)
      at PluginManager.spawn (/home/dennis/go/src/sportsplaner/node_modules/serverless/lib/classes/PluginManager.js:530:17)
      at /home/dennis/go/src/sportsplaner/node_modules/serverless/lib/plugins/deploy/deploy.js:122:50
  From previous event:
      at Object.before:deploy:deploy [as hook] (/home/dennis/go/src/sportsplaner/node_modules/serverless/lib/plugins/deploy/deploy.js:102:22)
      at /home/dennis/go/src/sportsplaner/node_modules/serverless/lib/classes/PluginManager.js:510:55
  From previous event:
      at PluginManager.invoke (/home/dennis/go/src/sportsplaner/node_modules/serverless/lib/classes/PluginManager.js:510:22)
      at /home/dennis/go/src/sportsplaner/node_modules/serverless/lib/classes/PluginManager.js:545:24
  From previous event:
      at PluginManager.run (/home/dennis/go/src/sportsplaner/node_modules/serverless/lib/classes/PluginManager.js:545:8)
      at /home/dennis/go/src/sportsplaner/node_modules/serverless/lib/Serverless.js:168:33
  From previous event:
      at Serverless.run (/home/dennis/go/src/sportsplaner/node_modules/serverless/lib/Serverless.js:155:74)
      at /home/dennis/go/src/sportsplaner/node_modules/serverless/scripts/serverless.js:50:26
      at processImmediate (internal/timers.js:456:21)
      at process.topLevelDomainCallback (domain.js:137:15)
  From previous event:
      at Object.<anonymous> (/home/dennis/go/src/sportsplaner/node_modules/serverless/scripts/serverless.js:50:4)
      at Module._compile (internal/modules/cjs/loader.js:1138:30)
      at Object.Module._extensions..js (internal/modules/cjs/loader.js:1158:10)
      at Module.load (internal/modules/cjs/loader.js:986:32)
      at Function.Module._load (internal/modules/cjs/loader.js:879:14)
      at Module.require (internal/modules/cjs/loader.js:1026:19)
      at require (internal/modules/cjs/helpers.js:72:18)
      at Object.<anonymous> (/home/dennis/go/src/sportsplaner/node_modules/serverless/bin/serverless.js:47:1)
      at Module._compile (internal/modules/cjs/loader.js:1138:30)
      at Object.Module._extensions..js (internal/modules/cjs/loader.js:1158:10)
      at Module.load (internal/modules/cjs/loader.js:986:32)
      at Function.Module._load (internal/modules/cjs/loader.js:879:14)
      at Function.executeUserEntryPoint [as runMain] (internal/modules/run_main.js:71:12)
      at /home/dennis/.nvm/versions/node/v12.17.0/lib/node_modules/npm/node_modules/libnpx/index.js:268:14

  Get Support --------------------------------------------
     Docs:          docs.serverless.com
     Bugs:          github.com/serverless/serverless/issues
     Issues:        forum.serverless.com

  Your Environment Information ---------------------------
     Operating System:          linux
     Node Version:              12.17.0
     Framework Version:         2.4.0 (local)
     Plugin Version:            4.0.4
     SDK Version:               2.3.2
     Components Version:        3.2.1

### Additional contract requirements

- In a service with functions using multiple runtimes, non-Node functions must not be treated as webpack functions, while Node functions remain eligible for webpack processing.
