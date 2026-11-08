ssm inclusions fail
<!--
1. Please check if an issue already exists so there are no duplicates
2. Fill out the whole template so we have a good overview on the issue
3. Do not remove any section of the template. If something is not applicable leave it empty but leave it in the Issue
4. Please follow the template, otherwise we'll have to ask you to update it
-->

# This is a Bug Report

## Description

#### Migration of [issue 240](https://github.com/serverless-heaven/serverless-webpack/issues/240) from serverless-webpack.

I’ve just tried to implement ssm secrets. I think I’ve done everything correctly but it looks like serverless.yml just won’t accept the `{ ${ssm:}` prefix the build fails using serverless-webpack, though this package seems unrelated, as from Alex:

From a quick glance, it looks like there's an issue because using SSM requires using an AWS account, which requires making a call with the awsProvider. The problem here is that the profile variable ${self:custom.profiles.${self:provider.stage}} hasn't been resolved yet, so it's not able to make the call.

```
Error: Profile ${self:custom.profiles.${self:provider.stage}} does not exist
    at Object.addProfileCredentials (/usr/local/lib/node_modules/serverless/lib/plugins/aws/provider/awsProvider.js:79:15)
    at AwsProvider.getCredentials (/usr/local/lib/node_modules/serverless/lib/plugins/aws/provider/awsProvider.js:209:12)
    at AwsProvider.request (/usr/local/lib/node_modules/serverless/lib/plugins/aws/provider/awsProvider.js:150:30)
    at Variables.getValueFromSsm (/usr/local/lib/node_modules/serverless/lib/classes/Variables.js:365:6)
```

And the SSM code calling the AWS provider is [here](https://github.com/serverless/serverless/blob/1159e5b01b4785dc43826ae899d12f074895ccfe/lib/classes/Variables.js#L364).

I don't think this is due to serverless-webpack specifically. It also seems like this could happen with S3 variable syntax or CF variable syntax as well. I wonder if the main issue is a large, complicated config file where some randomness (adding / removing serverless-webpack) can mean the provider value isn't resolved by the time it tries to get SSM.

#### working benchmark:
```
service: webpack-ssm

plugins:
  - serverless-webpack

provider:
  name: aws
  runtime: nodejs6.10
  environment:
    variable1: ${ssm:test-key}

functions:
  hello:
    handler: handler.hello
```

For bug reports:
* What went wrong?

When deploying the below serverless.yml we get the following error:

`Profile ${self:custom.profiles.${self:provider.stage}} does not exist`

If I hard code the profile name in the profile block instead I get the following error:

`  Inaccessible host: 'ssm.'`. This service may not be available in the `${opt:region, self:custom.regions.${self:provider.stage}}' region.`

which makes it look like its not exploding the custom section properly if `ssm:` is present

I've also run a raw SLS without serverless-webpack and it deploys correctly.

* What did you expect should have happened?
deployment
* What was the config you used?
```yaml
service: paymentGatewayService
frameworkVersion: ^1.22.0

provider:
  name: aws
  runtime: nodejs6.10
  stage: ${opt:stage, self:custom.defaultStage}
  profile: ${self:custom.profiles.${self:provider.stage}}
  region: ${opt:region, self:custom.regions.${self:provider.stage}}
  memorySize: 128 # this parameter doesnt only change how much memory is available but also CPU's and container life.
  timeout: 20
  environment:
    DEPLOY_REGION: ${opt:region, self:provider.region}
    INTEGRA_API_PASS: ${self:custom.gateways.integraPay.api-password.${self:provider.stage}}
    INTEGRA_USER_NAME: ${self:custom.gateways.integraPay.api-username.${self:provider.stage}}
    INTEGRA_API_URL: ${self:custom.gateways.integraPay.api-url.${self:provider.stage}}
    INTEGRA_VAULT_URL: ${self:custom.gateways.integraPay.api-vault.${self:provider.stage}}
    PAYMENTGATEWAY_TABLE_NAME: paymentgateways-${opt:stage, self:provider.stage}
    PAYMENTS_TABLE_NAME: payments-${opt:stage, self:provider.stage}
    #functions that we dont want exposed via HTTP
    POST_PAYMENT: ${self:provider.stage}-${self:custom.grub}-postPayment
    #internal lambda links for non-http endpoints
    POST_TRANSACTION_STATUS_UPDATE: ${self:provider.stage}-transactions-api-postTransactionStatusUpdate
  iamRoleStatements:
    - Effect: Allow
      Action:
        - lambda:InvokeFunction
        - lambda:InvokeAsync
      Resource: "*"
package:
  #individually: true
  include:
    - configurators
    - lib
  exclude:
    - tmp
    - .git
    - .idea
plugins:
  - serverless-mocha-plugin
  #- serverless-snyk
  - serverless-dynamodb-local
  #- serverless-offline
  - serverless-webpack
  - serverless-plugin-bind-deployment-id
custom:
  local: ${file(../developerSpecific.yml)} #a file for developer specific values
  webpackIncludeModules: true
  grub: paymentgateways-api
  defaultStage: dev
  defaultBasePath: paymentgateways
  defaultDomain: ${self:custom.local.customDomainName} #points to developer domain
  profiles:
    dev: default
    uat: mpa-uat
    prod: mpa-serverless-admin
  #defaultRegion: us-east-1
  regions:
    dev: us-east-1
    uat: ap-southeast-2
    prod: us-east-1
  basePath:
    dev: paymentgateways
    uat: paymentgateways
    prod: paymentgateways
  domainName:
    dev: ${self:custom.local.customDomainName}
    uat: ${self:custom.local.customDomainNameUat}
    prod: api.tobedefined.com
  gateways:
    integraPay:
      api-username:
        dev: ${self:custom.local.integraPayApiUsername-uat}
        uat: ${self:custom.local.integraPayApiUsername-uat}
        prod: ${self:custom.local.integraPayApiUsername-uat}
      api-password:
        dev: ${self:custom.local.integraPayApiPassword-uat}
        #dev: ${ssm:mpa/uat/integra/api/pass~true}
        #dev: ${ssm:${self:custom.local.integraPayApiPassword}~true}
        uat: ${self:custom.local.integraPayApiPassword-uat}
        prod: ${self:custom.local.integraPayApiPassword-uat}
      api-url:
        dev: https://apitest.integrapay.com.au/basic/PayLinkService.svc?WSDL
        uat: https://apitest.integrapay.com.au/basic/PayLinkService.svc?WSDL
        prod:  https://api.integrapay.com.au/basic/PayLinkService.svc?WSDL
      api-vault:
        dev: https://testpayments.integrapay.com.au/API/API.ashx
        uat: https://testpayments.integrapay.com.au/API/API.ashx
        prod:  https://payments.integrapay.com.au/API/API.ashx

functions:
  pingPaymentgateways:
    handler: handler.ping
    name: ${self:provider.stage}-${self:custom.grub}-ping
    events:
    - http:
        path: ping
        method: get
  getPayments:
    handler: handler.getPayments
    name: ${self:provider.stage}-${self:custom.grub}-getPayments
    description: returns a list of payments. could be called by other services
    events:
    - http:
        path: /
        method: get
  getPaymentById:
    handler: handler.getPaymentById
    name: ${self:provider.stage}-${self:custom.grub}-getPaymentById
    description: get a single payment record. could be called by other services
    events:
    - http:
        path: /{paymentId}
        method: get
  postPayment:
    handler: handler.postPayment
    name: ${self:provider.stage}-${self:custom.grub}-postPayment
    description: The endpoint to post payments to internally
  postPaymentInstrument:
    handler: handler.postPaymentInstrument
    name: ${self:provider.stage}-${self:custom.grub}-postPaymentInstrument
    description: The endpoint to post new or updated payment instruments to internally for gateway configuration
  postUser:
    handler: handler.postUser
    name: ${self:provider.stage}-${self:custom.grub}-postUser
    description: The endpoint to post new users to internally for gateway configuration
  processPayment:
    handler: handler.processPayment
    name: ${self:provider.stage}-${self:custom.grub}-processPayment
    description: Triggered to push transactions to the external gateways
    events:
      - stream:
        "Fn::Join": ["", ["arn:aws:dynamodb:", {"Ref": "AWS::Region"}, ":", {"Ref": "AWS::AccountId"}, ":table/", "payments-${opt:stage, self:provider.stage}", "/stream/*"]]
  processGatewayUpdates:
    handler: handler.processGatewayUpdates
    timeout: 60
    name: ${self:provider.stage}-${self:custom.grub}-processGatewayUpdates
    description: Scheduled function that polls the gateways and processes their responses
    events:
    - schedule: rate(5 minutes)
  requestVaultSession:
    handler: handler.requestVaultSession
    name: ${self:provider.stage}-${self:custom.grub}-requestVaultSession
    description: Function to get a vault response from a gateway
  checkVaultSession:
    handler: handler.checkVaultSession
    name: ${self:provider.stage}-${self:custom.grub}-checkVaultSession
    description: simple internal endpoint that looks up a user to see if they have a card attached.
  #processVaultSession:
  #  handler: handler.processVaultSession
  #  name: ${self:provider.stage}-${self:custom.grub}-processVaultSession
  #  description: Function to get card details
  getGateways:
    handler: handler.getGateways
    name: ${self:provider.stage}-${self:custom.grub}-getGateways
    events:
    - http:
        path: gateways
        method: get
        cors: true
  getGatewayById:
    handler: handler.getGatewayById
    name: ${self:provider.stage}-${self:custom.grub}-getGatewayById
    events:
    - http:
        path: gateways/{gatewayId}
        method: get
        cors: true
  getGatewayPaymentMethodConfigurations:
    handler: handler.getGatewayPaymentMethodConfigurations
    name: ${self:provider.stage}-${self:custom.grub}-getGatewayPaymentMethodConfigurations
    events:
    - http:
        path: gateways/{gatewayId}/paymentMethodConfigurations
        method: get
        cors: true
  getGatewayPaymentMethodConfigurationById:
    handler: handler.getGatewayPaymentMethodConfigurationById
    name: ${self:provider.stage}-${self:custom.grub}-getGatewayPaymentMethodConfigurationById
    events:
    - http:
        path: gateways/{gatewayId}/paymentMethodConfigurations/{paymentMethodConfigurationId}
        method: get
        cors: true
  deleteGatewayPaymentConfigurationById:
    handler: handler.deleteGatewayPaymentConfigurationById
    name: ${self:provider.stage}-${self:custom.grub}-deleteGatewayPaymentConfigurationById
    events:
    - http:
        path: gateways/{gatewayId}/paymentMethodConfigurations/{paymentMethodConfigurationId}
        method: delete
        cors: true
# Resources are essentially CloudFormation scripts. These are kept in the configurators folder
resources:
  Resources:
    __deployment__:
      Properties:
        Description: Deployment alias for resources that depend on deployment id
    PaymentsTable:
      $ref: ./configurators/paymentsTable.yaml
    PushPaymentLambdaMapping:
      $ref: ./configurators/processPaymentEventSourceMapping.yaml
    PaymentGatewaysTable:
      $ref: ./configurators/paymentGatewaysTable.yaml
    IamPolicyLambdaDynamo:
      $ref: ./configurators/iamPolicyLambdaDynamo.yaml
    PathMapping:
      $ref: ./configurators/pathMapping.yaml
    ApiGatewayStage:
      $ref: ./configurators/apiGatewayStage.yaml
```

* What stacktrace or error message from your provider did you see?
```
Error: Profile ${self:custom.profiles.${self:provider.stage}} does not exist
    at Object.addProfileCredentials (/usr/local/lib/node_modules/serverless/lib/plugins/aws/provider/awsProvider.js:79:15)
    at AwsProvider.getCredentials (/usr/local/lib/node_modules/serverless/lib/plugins/aws/provider/awsProvider.js:209:12)
    at AwsProvider.request (/usr/local/lib/node_modules/serverless/lib/plugins/aws/provider/awsProvider.js:150:30)
    at Variables.getValueFromSsm (/usr/local/lib/node_modules/serverless/lib/classes/Variables.js:365:6)
    at Variables.getValueFromSource (/usr/local/lib/node_modules/serverless/lib/classes/Variables.js:184:19)
    at property.match.forEach (/usr/local/lib/node_modules/serverless/lib/classes/Variables.js:98:40)
    at Array.forEach (<anonymous>)
    at Variables.populateProperty (/usr/local/lib/node_modules/serverless/lib/classes/Variables.js:89:43)
    at deepMapValues (/usr/local/lib/node_modules/serverless/lib/classes/Variables.js:69:45)
    at deepMapValues (/usr/local/lib/node_modules/serverless/lib/classes/Variables.js:64:14)
    at deepMapValuesIteratee (/usr/local/lib/node_modules/serverless/lib/classes/Variables.js:54:25)
    at /usr/local/lib/node_modules/serverless/node_modules/lodash/lodash.js:13379:38
    at /usr/local/lib/node_modules/serverless/node_modules/lodash/lodash.js:4944:15
    at baseForOwn (/usr/local/lib/node_modules/serverless/node_modules/lodash/lodash.js:3001:24)
    at Function.mapValues (/usr/local/lib/node_modules/serverless/node_modules/lodash/lodash.js:13378:7)
    at deepMapValues (/usr/local/lib/node_modules/serverless/lib/classes/Variables.js:62:39)
    at deepMapValuesIteratee (/usr/local/lib/node_modules/serverless/lib/classes/Variables.js:54:25)
    at /usr/local/lib/node_modules/serverless/node_modules/lodash/lodash.js:13379:38
    at /usr/local/lib/node_modules/serverless/node_modules/lodash/lodash.js:4944:15
    at baseForOwn (/usr/local/lib/node_modules/serverless/node_modules/lodash/lodash.js:3001:24)
    at Function.mapValues (/usr/local/lib/node_modules/serverless/node_modules/lodash/lodash.js:13378:7)
    at deepMapValues (/usr/local/lib/node_modules/serverless/lib/classes/Variables.js:62:39)
    at deepMapValuesIteratee (/usr/local/lib/node_modules/serverless/lib/classes/Variables.js:54:25)
    at /usr/local/lib/node_modules/serverless/node_modules/lodash/lodash.js:13379:38
    at /usr/local/lib/node_modules/serverless/node_modules/lodash/lodash.js:4944:15
    at baseForOwn (/usr/local/lib/node_modules/serverless/node_modules/lodash/lodash.js:3001:24)
    at Function.mapValues (/usr/local/lib/node_modules/serverless/node_modules/lodash/lodash.js:13378:7)
    at deepMapValues (/usr/local/lib/node_modules/serverless/lib/classes/Variables.js:62:39)
    at deepMapValuesIteratee (/usr/local/lib/node_modules/serverless/lib/classes/Variables.js:54:25)
    at /usr/local/lib/node_modules/serverless/node_modules/lodash/lodash.js:13379:38
    at /usr/local/lib/node_modules/serverless/node_modules/lodash/lodash.js:4944:15
    at baseForOwn (/usr/local/lib/node_modules/serverless/node_modules/lodash/lodash.js:3001:24)
    at Function.mapValues (/usr/local/lib/node_modules/serverless/node_modules/lodash/lodash.js:13378:7)
    at deepMapValues (/usr/local/lib/node_modules/serverless/lib/classes/Variables.js:62:39)
    at deepMapValuesIteratee (/usr/local/lib/node_modules/serverless/lib/classes/Variables.js:54:25)
    at /usr/local/lib/node_modules/serverless/node_modules/lodash/lodash.js:13379:38
    at /usr/local/lib/node_modules/serverless/node_modules/lodash/lodash.js:4944:15
    at baseForOwn (/usr/local/lib/node_modules/serverless/node_modules/lodash/lodash.js:3001:24)
    at Function.mapValues (/usr/local/lib/node_modules/serverless/node_modules/lodash/lodash.js:13378:7)
    at deepMapValues (/usr/local/lib/node_modules/serverless/lib/classes/Variables.js:62:39)
    at Variables.populateObject (/usr/local/lib/node_modules/serverless/lib/classes/Variables.js:67:5)
    at Variables.populateService (/usr/local/lib/node_modules/serverless/lib/classes/Variables.js:43:17)
    at Serverless.run (/usr/local/lib/node_modules/serverless/lib/Serverless.js:86:27)
    at serverless.init.then (/usr/local/lib/node_modules/serverless/bin/serverless:39:50)
    at <anonymous>
```

Similar or dependent issue(s):
* Initially was [raised at serverless-webpack](https://github.com/serverless-heaven/serverless-webpack/issues/240)

* ***Serverless-Webpack Version you're using***:

    "serverless-webpack": "3.1.0",

* ***Webpack version you're using***:
    "webpack": "3.6.0",
* ***Serverless Framework Version you're using***:
    "serverless": "1.23.0",
* ***Operating System***:
macos
* ***Stack Trace (if available)***:
