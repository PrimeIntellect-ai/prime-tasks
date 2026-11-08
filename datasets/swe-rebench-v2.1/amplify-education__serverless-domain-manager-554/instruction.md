Error: Unable to setup base domain mappings for 'domain_name'
### Community Note

* Please vote on this issue by adding a 👍 [reaction](https://blog.github.com/2016-03-10-add-reactions-to-pull-requests-issues-and-comments/) to the original issue to help the community and maintainers prioritize this request
* Please do not leave "+1" or "me too" comments, they generate extra noise for issue followers and do not help prioritize the request
* If you are interested in working on this issue or have submitted a pull request, please leave a comment

## Bug Report

I`m try to deploy my AWS resources, but unfortunately  I'm getting the following message:
**Error:
Error: Unable to setup base domain mappings for 'api.reffy.pro':
Unsupported apiGateway.restApiId object**

**Command Run**
`sls deploy`

**Console Output**
```Error:
Error: Unable to setup base domain mappings for 'api.reffy.pro':
Unsupported apiGateway.restApiId object
```

**Domain Manager Configuration**
Replace this with your own `serverless.yml` file (anonymized, of course) to help us better resolve your issue.
```yaml
custom:
  customDomain:
    domainName: YOUR_DOMAIN_NAME
    stage: ${self:provider.stage}
    basePath: plugin
    createRoute53Record: true
    createRoute53IPv6Record: false
    endpointType: REGIONAL
    securityPolicy: tls_1_2
    apiType: rest
    autoDomain: true
    preserveExternalPathMappings: true
provider:
  name: aws
  region: eu-central-1
  stage: prod
  runtime: nodejs16.x
  apiGateway:
    restApiId: !Ref EmployeeApiGateway
    restApiRootResourceId:
      Fn::GetAtt:
        - EmployeeApiGateway
        - RootResourceId
resources:
  Resources:
    SQSEmployeeQueue:
      Type: AWS::SQS::Queue
      Properties:
        QueueName: "SQSEmployeeQueue.fifo"
        FifoQueue: true
        ContentBasedDeduplication: true
        DelaySeconds: 30
    EmployeeApiGateway:
      Type: AWS::ApiGateway::RestApi
      Properties:
        Name: "test-api-gateway"
        Body:
          openapi: 3.0.3
          paths:
            /employee:
              post:
                requestBody:
                  content:
                    application/json:
                x-amazon-apigateway-integration:
                  credentials: !GetAtt ApiGatewayToSQSRole.Arn
                  httpMethod: "POST"
                  uri: !Sub "arn:aws:apigateway:${AWS::Region}:sqs:path/${AWS::AccountId}/${SQSEmployeeQueue.QueueName}"
                  responses:
                    default:
                      statusCode: "200"
                      responseParameters:
                        method.response.header.Access-Control-Allow-Headers: '''*'''
                        method.response.header.Access-Control-Allow-Methods: '''*'''
                        method.response.header.Access-Control-Allow-Origin: '''*'''
                        responseTemplates:
                          application/json: |
                            {}
                  requestParameters:
                    integration.request.header.Content-Type: "'application/x-www-form-urlencoded'"
                    'integration.request.querystring.MessageGroupId': "'UniqueQueue'"
                  requestTemplates:
                    application/json: "Action=SendMessage&MessageGroupId='group-message-employee'&MessageBody=$util.urlEncode($input.body)"
                  passthroughBehavior: "never"
                  type: "aws"
```

**Versions**
-  node: v18.11.0
-  npm: 8.19.2
-  serverless-domain-manager: "^6.2.1"
-  serverless: "^3.26.0"
