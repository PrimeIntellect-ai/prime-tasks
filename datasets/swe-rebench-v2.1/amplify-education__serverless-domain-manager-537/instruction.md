getCustomDomainInfo does not work in Jakarta Region as APIGatewayV2 has not been supported in this region yet
<!--- Please keep this note for the community --->

### Community Note

* Please vote on this issue by adding a 👍 [reaction](https://blog.github.com/2016-03-10-add-reactions-to-pull-requests-issues-and-comments/) to the original issue to help the community and maintainers prioritize this request
* Please do not leave "+1" or "me too" comments, they generate extra noise for issue followers and do not help prioritize the request
* If you are interested in working on this issue or have submitted a pull request, please leave a comment

<!--- Thank you for keeping this note for the community --->

## Bug Report

**Error Description**
Unable to  use getCustomDomainInfo function in ap-southeast-3 (Jakarta region) since this function had used the APIGatewayV2

**Command Run**
`sls create_domain`

**Console Output**
```sh
Error:
Error: Unable to fetch information about <DOMAIN_NAME>
    at APIGatewayWrapper.<anonymous> (/Users/<USER>/<Project>/<Service>/node_modules/serverless-domain-manager/dist/src/aws/api-gateway-wrapper.js:110:27)
    at Generator.throw (<anonymous>)
    at rejected (/Users/<USER>/<Project>/<Service>/node_modules/serverless-domain-manager/dist/src/aws/api-gateway-wrapper.js:6:65)
    at process.processTicksAndRejections (node:internal/process/task_queues:95:5)
```

**Domain Manager Configuration**
```yaml
custom:
  customDomain:
    domainName: ${self:provider.domain}
    hostedZoneId: ${self:provider.hostzoneid}
    basePath: ''
    certificateArn: ${self:provider.certificatearn}
    stage: ${self:provider.stage}
    createRoute53Record: true
    endpointType: REGIONAL
    securityPolicy: TLS_1_0
    autoDomain: true

provider:
  name: aws
  runtime: nodejs14.x
  memorySize: 128
  domain: <$DOMAIN>
  hostzoneid: <$HOSTZONE_ID>
  certificatearn: <$CERT_ARN>
  stage: staging
  region: ${opt:region, 'ap-southeast-3'}
  environment: ${file(env.yml):${self:provider.stage}}
```

**Versions**
- Domain Manager version(s): [6.2.2]
- Node/npm version: [Node 18.13.0/ npm 8.19.3]
- Serverless Version: [3.26.0]
- Lambda Code [Javascript

**Possible Solution**
[HIDDEN]

### Additional contract requirements

- In the `ap-southeast-3` region, `sls create_domain` must be able to retrieve usable information about the custom domain rather than fail because the region does not support API Gateway v2.
