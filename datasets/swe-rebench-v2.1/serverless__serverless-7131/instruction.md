-c option doesn't work for sls deploy command
# Bug Report

## Description

<!-- Please use https://forum.serverless.com, StackOverflow or other forums for Q&A -->
<!-- Please answer ALL the question below. Otherwise we probably have to close the issue due to missing information -->

1. What did you do?

I tried to run `sls deploy -c myconfig.yml`, according to the official site:
https://serverless.com/framework/docs/providers/aws/cli-reference/deploy/

1. What happened?

```
 Serverless Error ---------------------------------------

  This command can only be run in a Serverless service directory. Make sure to reference a valid config file in the current working directory if you're using a custom config file
```

1. What should've happened?

Deploy command should get success.

1. What's the content of your `serverless.yml` file?

my.yml is like this:
```
service: amazon-ses2

provider:
  name: aws
  runtime: python3.8
  memorySize: 128
  region: ap-northeast-1
  iamRoleStatements:
    - Effect: "Allow"
      Action:
        - "ses:SendEmail"
      Resource: "*"

functions:
  send_mail_2:
    handler: handler.send_mail
    environment:
      SES_REGION: ${opt:ses_region, 'us-west-2'}
      SES_FROM_ADDR: ${opt:from_addr}
      SES_FROM_NAME: ${opt:from_name}~/Develop/kdnakt/serverless
```


1. What's the output you get when you use the `SLS_DEBUG=*` environment variable (e.g. `SLS_DEBUG=* serverless deploy`)

```
$ SLS_DEBUG=* sls deploy -c my.yml
Serverless: Load command interactiveCli
Serverless: Load command config
Serverless: Load command config:credentials
Serverless: Load command config:tabcompletion
Serverless: Load command config:tabcompletion:install
Serverless: Load command config:tabcompletion:uninstall
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
Serverless: Load command login
Serverless: Load command logout
Serverless: Load command generate-event
Serverless: Load command test
Serverless: Load command dashboard

  Serverless Error ---------------------------------------

  ServerlessError: This command can only be run in a Serverless service directory. Make sure to reference a valid config file in the current working directory if you're using a custom config file
      at PluginManager.validateServerlessConfigDependency (/usr/local/lib/node_modules/serverless/lib/classes/PluginManager.js:546:15)
      at PluginManager.invoke (/usr/local/lib/node_modules/serverless/lib/classes/PluginManager.js:474:10)
      at getHooks.reduce.then (/usr/local/lib/node_modules/serverless/lib/classes/PluginManager.js:524:24)
  From previous event:
      at PluginManager.run (/usr/local/lib/node_modules/serverless/lib/classes/PluginManager.js:524:8)
      at variables.populateService.then (/usr/local/lib/node_modules/serverless/lib/Serverless.js:115:33)
      at runCallback (timers.js:705:18)
      at tryOnImmediate (timers.js:676:5)
      at processImmediate (timers.js:658:5)
      at process.topLevelDomainCallback (domain.js:120:23)
  From previous event:
      at Serverless.run (/usr/local/lib/node_modules/serverless/lib/Serverless.js:102:74)
      at serverless.init.then (/usr/local/lib/node_modules/serverless/bin/serverless.js:72:30)
      at /usr/local/lib/node_modules/serverless/node_modules/graceful-fs/graceful-fs.js:111:16
      at /usr/local/lib/node_modules/serverless/node_modules/graceful-fs/graceful-fs.js:45:10
      at FSReqWrap.oncomplete (fs.js:141:20)
  From previous event:
      at initializeErrorReporter.then (/usr/local/lib/node_modules/serverless/bin/serverless.js:72:8)
      at runCallback (timers.js:705:18)
      at tryOnImmediate (timers.js:676:5)
      at processImmediate (timers.js:658:5)
      at process.topLevelDomainCallback (domain.js:120:23)
  From previous event:
      at Object.<anonymous> (/usr/local/lib/node_modules/serverless/bin/serverless.js:61:4)
      at Module._compile (internal/modules/cjs/loader.js:689:30)
      at Object.Module._extensions..js (internal/modules/cjs/loader.js:700:10)
      at Module.load (internal/modules/cjs/loader.js:599:32)
      at tryModuleLoad (internal/modules/cjs/loader.js:538:12)
      at Function.Module._load (internal/modules/cjs/loader.js:530:3)
      at Function.Module.runMain (internal/modules/cjs/loader.js:742:12)
      at startup (internal/bootstrap/node.js:283:19)
      at bootstrapNodeJSCore (internal/bootstrap/node.js:743:3)

  Get Support --------------------------------------------
     Docs:          docs.serverless.com
     Bugs:          github.com/serverless/serverless/issues
     Issues:        forum.serverless.com

  Your Environment Information ---------------------------
     Operating System:          darwin
     Node Version:              10.15.0
     Framework Version:         1.59.3
     Plugin Version:            3.2.6
     SDK Version:               2.2.1
     Components Core Version:   1.1.2
     Components CLI Version:    1.4.0
```


Similar or dependent issues:

- #12345

### Additional contract requirements

- Running `sls deploy -c <config file>` in a directory where the given file is a valid service configuration must load the service from that file, the same way `--config <config file>` does.
