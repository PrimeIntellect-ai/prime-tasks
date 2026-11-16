Stage is added twice and erroneous
Hi there

if I define the stage with a variable the stage is added twice and the second add is erroneous because the variable is not mapped
**myLambda-myStage-${self:custom.stage}**

***reproduce***
```
serverless create --template aws-java-maven --path myLambda
```
in the created directory:
change serverless.yml to
```
service: myLambda
custom:
  stage: myStage
provider:
  name: aws
  runtime: java8
  stage: ${self:custom.stage}
package:
  artifact: target/hello-dev.jar
functions:
  hello:
    handler: com.serverless.Handler
plugins:
  - serverless-aws-alias
```
then run commands
```
mvn clean package
npm install --save serverless-aws-alias
serverless deploy -v
```
The output of the deploy step is
```
Serverless: Packaging service...
Serverless: Preparing alias ...
Serverless: Processing custom resources
Serverless: Removing resources:
Serverless: Processing functions
Serverless: Creating Stack...
Serverless: Checking Stack create progress...
CloudFormation - CREATE_IN_PROGRESS - AWS::CloudFormation::Stack - myLambda-myStage
CloudFormation - CREATE_IN_PROGRESS - AWS::S3::Bucket - ServerlessDeploymentBucket
CloudFormation - CREATE_IN_PROGRESS - AWS::S3::Bucket - ServerlessDeploymentBucket
CloudFormation - CREATE_COMPLETE - AWS::S3::Bucket - ServerlessDeploymentBucket
CloudFormation - CREATE_COMPLETE - AWS::CloudFormation::Stack - myLambda-myStage
Serverless: Stack create finished...

  Serverless Error ---------------------------------------

     The stack alias name "myLambda-myStage-${self:custom.stage}"
     is not valid. A service name should only contain alphanumeric
     (case sensitive) and hyphens. It should start with an
     alphabetic character and shouldn't exceed 128 characters.

  Get Support --------------------------------------------
     Docs:          docs.serverless.com
     Bugs:          github.com/serverless/serverless/issues
     Forums:        forum.serverless.com
     Chat:          gitter.im/serverless/serverless

  Your Environment Information -----------------------------
     OS:                 linux
     Node Version:       6.9.1
     Serverless Version: 1.13.2
```

Best regards
