Incorrect hosted zone chosen when attempting to create a custom domain name
### Error Description
We appear to have hit a bug in how serverless automatically selects the appropriate hosted zone for some requested domain names. Specifically, when two domains exist, say serverlessdevapi.mydomain.com as well as api.mydomain.com, and our configuration calls for creating of a custom name of serverlessdevapi.mydomain.com, serverless selects the api.mydomain.com incorrectly when attempting to create the A record.
We were able to temporarily workaround the issue in this instance by explicitly specifying hostedZoneId as the ID of mydomain.com to force that zone to be used.

Note: This peripherally looks the same as https://github.com/amplify-education/serverless-domain-manager/issues/182, which was resolved a couple of years back.

### Command Run
`OUR_ENV=dev DOMAIN_NAME=serverlessdevapi.mydomain.com serverless create_domain --stage dev`

### Console Output
```
11:34:24  > serverless create_domain --stage dev
11:34:24

Environment: darwin, node 16.19.1, framework 3.37.0 (local) 3.36.0v (global), plugin 7.2.0, SDK 4.5.1
Docs:        docs.serverless.com
Support:     forum.serverless.com
Bugs:        github.com/serverless/serverless/issues
11:34:32
11:34:32  Error:
11:34:32  Error: Unable to create domain 'serverlessdevapi.mydomain.com':
11:34:32  Failed to UPSERT A Alias for 'serverlessdevapi.mydomain.com':
11:34:32  [RRSet with DNS name serverlessdevapi.mydomain.com. is not permitted in zone api.mydomain.com., RRSet with DNS name serverlessdevapi.mydomain.com. is not permitted in zone api.mydomain.com.]
11:34:32      at ServerlessCustomDomain.<anonymous> (/tmp/workspace/sample-lambda/lambda/node_modules/serverless-domain-manager/dist/src/index.js:257:23)
11:34:32      at Generator.throw (<anonymous>)
11:34:32      at rejected (/tmp/workspace/sample-lambda/lambda/node_modules/serverless-domain-manager/dist/src/index.js:6:65)
11:34:32      at processTicksAndRejections (internal/process/task_queues.js:96:5)
```


### Domain Manager Configuration
```
custom:
  customDomain:
    basePath: ""
    enabled: true
    createRoute53Record: true
    domainName: serverlessdevapi.mydomain.com
    stage: dev
    certificateName: '*.mydomain.com'
```
### Versions
```
Domain Manager version(s): 7.1.2
Node/npm version: Node 16
Serverless Version: 3.37.0
Lambda Code JavaScript
```
https://github.com/amplify-education/serverless-domain-manager/blame/1dcb0828039563d5f195f336bf7a3e929110591f/src/aws/route53-wrapper.ts#L67
