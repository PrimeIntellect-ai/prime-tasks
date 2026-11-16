Version 6.4.2 causes error setting base path mappings for API Gateway V1
<!--- Please keep this note for the community --->

### Community Note

* Please vote on this issue by adding a 👍 [reaction](https://blog.github.com/2016-03-10-add-reactions-to-pull-requests-issues-and-comments/) to the original issue to help the community and maintainers prioritize this request
* Please do not leave "+1" or "me too" comments, they generate extra noise for issue followers and do not help prioritize the request
* If you are interested in working on this issue or have submitted a pull request, please leave a comment

<!--- Thank you for keeping this note for the community --->

## Bug Report

**Error Description**

Since our pipeline picked up and used version 6.4.2 it has been failing with an error saying that API Gateway V1 doesn't support the slash character (/) in base path mappings. However this is not the case it is simply that V2 of the API needs to be used for this to work, even for V1.

Please ref to this discussion around something similar using Terraform that mentions the CLI of the same for AWS functionality used here: https://github.com/hashicorp/terraform-provider-aws/issues/21986#issuecomment-996231026

Our build works fine if we set the version of this plugin to 6.4.1

**Command Run**
`sls deploy`.

**Console Output**
```sh
Error:
--
234 | Error: V1 - Unable to update base path mapping for '###.#####.####.com':
235 | API Gateway V1 doesn't support the slash character (/) in base path mappings. To create a multi-level base path mapping, use API Gateway V2.
236 | at APIGatewayV1Wrapper.<anonymous> (/codebuild/output/src/#######/node_modules/serverless-domain-manager/dist/src/aws/api-gateway-v1-wrapper.js:144:23)
237 | at Generator.throw (<anonymous>)
238 | at rejected (/codebuild/output/src/#######/node_modules/serverless-domain-manager/dist/src/aws/api-gateway-v1-wrapper.js:6:65)
239 | at process.processTicksAndRejections (node:internal/process/task_queues:95:5)
240 | ERROR [deploy_serverless]: sls deploy failed
```

**Domain Manager Configuration**
```yaml
custom:
  customDomain:
    domainName: api.blah.blah.com
    basePath: this/is/my/basepath
    stage: dev
    createRoute53Record: false
    endpointType: 'regional'
```

**Versions**
- Domain Manager version(s): 6.4.2
- Node/npm version: 18.14.0 / 8
- Serverless Version: 3.72.0
- Lambda Code: JavaScript
