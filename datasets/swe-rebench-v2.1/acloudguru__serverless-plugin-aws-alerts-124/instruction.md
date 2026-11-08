Support for multiple topics with existing ARN, does not function correctly
<!--
1. Please check if an issue already exists so there are no duplicates
2. Fill out the whole template so we have a good overview on the issue
3. Do not remove any section of the template. If something is not applicable leave it empty but leave it in the Issue
4. Please follow the template, otherwise we'll have to ask you to update it
-->

# This is a (Bug Report)

## Description

For bug reports:
* What went wrong?
A type error when trying to use multiple topics
* What did you expect should have happened?
https://github.com/ACloudGuru/serverless-plugin-aws-alerts#multiple-topic-definitions
I should have been able to define multiple topics for each alarm to utilize a different topic
* What was the config you used?

topics:
      highPriority:
        ok:
          topic: arn:aws:sns:${self:custom.pRegion}:${self:custom.pAccountId}:${highTopicName}
        alarm:
          topic: arn:aws:sns:${self:custom.pRegion}:${self:custom.pAccountId}:${highTopicName}

      lowPriority:
        ok:
          topic: arn:aws:sns:${self:custom.pRegion}:${self:custom.pAccountId}:${lowTopicName}
        alarm:
          topic: arn:aws:sns:${self:custom.pRegion}:${self:custom.pAccountId}:${lowTopicName}

* What stacktrace or error message from your provider did you see?
  Type Error ---------------------------------------------

  TypeError: Cannot read property 'ok' of undefined
      at definition.okActions.map.alertTopic (C:\Users\Ryan.dincher\CSA_APPS\SLP\Repos\Fastlane\slp-api\node_modules\serverless-plugin-aws-alerts\src\index.js:100:48)
      at Array.map (<anonymous>)
      at AlertsPlugin.getAlarmCloudFormation (C:\Users\Ryan.dincher\CSA_APPS\SLP\Repos\Fastlane\slp-api\node_modules\serverless-plugin-aws-alerts\src\index.js:97:28)
      at alarms.reduce (C:\Users\Ryan.dincher\CSA_APPS\SLP\Repos\Fastlane\slp-api\node_modules\serverless-plugin-aws-alerts\src\index.js:287:25)
      at Array.reduce (<anonymous>)
      at serverless.service.getAllFunctions.forEach (C:\Users\Ryan.dincher\CSA_APPS\SLP\Repos\Fastlane\slp-api\node_modules\serverless-plugin-aws-alerts\src\index.js:285:38)
      at Array.forEach (<anonymous>)
      at AlertsPlugin.compileAlarms (C:\Users\Ryan.dincher\CSA_APPS\SLP\Repos\Fastlane\slp-api\node_modules\serverless-plugin-aws-alerts\src\index.js:277:47)
      at AlertsPlugin.compile (C:\Users\Ryan.dincher\CSA_APPS\SLP\Repos\Fastlane\slp-api\node_modules\serverless-plugin-aws-alerts\src\index.js:364:10)
      at BbPromise.reduce (C:\Users\Ryan.dincher\AppData\Roaming\npm\node_modules\serverless\lib\classes\PluginManager.js:489:55)
      at tryCatcher (C:\Users\Ryan.dincher\AppData\Roaming\npm\node_modules\serverless\node_modules\bluebird\js\release\util.js:16:23)
      at Object.gotValue (C:\Users\Ryan.dincher\AppData\Roaming\npm\node_modules\serverless\node_modules\bluebird\js\release\reduce.js:168:18)
      at Object.gotAccum (C:\Users\Ryan.dincher\AppData\Roaming\npm\node_modules\serverless\node_modules\bluebird\js\release\reduce.js:155:25)
      at Object.tryCatcher (C:\Users\Ryan.dincher\AppData\Roaming\npm\node_modules\serverless\node_modules\bluebird\js\release\util.js:16:23)
      at Promise._settlePromiseFromHandler (C:\Users\Ryan.dincher\AppData\Roaming\npm\node_modules\serverless\node_modules\bluebird\js\release\promise.js:547:31)
      at Promise._settlePromise (C:\Users\Ryan.dincher\AppData\Roaming\npm\node_modules\serverless\node_modules\bluebird\js\release\promise.js:604:18)
      at Promise._settlePromise0 (C:\Users\Ryan.dincher\AppData\Roaming\npm\node_modules\serverless\node_modules\bluebird\js\release\promise.js:649:10)
      at Promise._settlePromises (C:\Users\Ryan.dincher\AppData\Roaming\npm\node_modules\serverless\node_modules\bluebird\js\release\promise.js:729:18)
      at _drainQueueStep (C:\Users\Ryan.dincher\AppData\Roaming\npm\node_modules\serverless\node_modules\bluebird\js\release\async.js:93:12)
      at _drainQueue (C:\Users\Ryan.dincher\AppData\Roaming\npm\node_modules\serverless\node_modules\bluebird\js\release\async.js:86:9)
      at Async._drainQueues (C:\Users\Ryan.dincher\AppData\Roaming\npm\node_modules\serverless\node_modules\bluebird\js\release\async.js:102:5)
      at Immediate.Async.drainQueues [as _onImmediate] (C:\Users\Ryan.dincher\AppData\Roaming\npm\node_modules\serverless\node_modules\bluebird\js\release\async.js:15:14)
      at runCallback (timers.js:705:18)
      at tryOnImmediate (timers.js:676:5)
      at processImmediate (timers.js:658:5)
      at process.topLevelDomainCallback (domain.js:121:23)

For feature proposals:
* What is the use case that should be solved. The more detail you describe this in the easier it is to understand for us.
* If there is additional config how would it look

Similar or dependent issues:

## Additional Data
  Your Environment Information ---------------------------
     Operating System:          win32
     Node Version:              10.14.1
     Framework Version:         1.58.0
     Plugin Version:            3.2.5
     SDK Version:               2.2.1
     Components Core Version:   1.1.2
     Components CLI Version:    1.4.0

The issue appears to be with the _addAlertTopic method.
When using multiple topics the topic that the Alarm subscribes to is a "custom Alarm".
If I provide an ARN to the ok/alarm action then the custom alarm is not added.
 [HIDDEN]

* ***Serverless Framework Version***:
* ***Stack Trace***:
* ***Provider Error messages***:

### Additional contract requirements

- Different alarms must be able to select different named topics for their `ok` and `alarm` actions.
- When a selected topic is configured with an existing SNS ARN, the corresponding alarm action must use that ARN directly without creating a replacement SNS topic.
