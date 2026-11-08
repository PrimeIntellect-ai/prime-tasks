Hosted Zone name matching broken in v7.3.1
<!--- Please keep this note for the community --->

### Community Note

* Please vote on this issue by adding a 👍 [reaction](https://blog.github.com/2016-03-10-add-reactions-to-pull-requests-issues-and-comments/) to the original issue to help the community and maintainers prioritize this request
* Please do not leave "+1" or "me too" comments, they generate extra noise for issue followers and do not help prioritize the request
* If you are interested in working on this issue or have submitted a pull request, please leave a comment

<!--- Thank you for keeping this note for the community --->

## Bug Report

**Error Description**
Custom domain creation fails when the hosted zone and the domain are the same.

For example, if an API has the domain `api.example.com` and the hosted zone is `api.example.com.`.

The following error is thrown: `Could not find hosted zone 'api.example.com'`

This bug has been introduced in v7.3.1; it works OK in v7.3.0

**Command Run**
`sls create_domain`

**Console Output**
```sh
Error: Unable to create domain '[REDACTED]':
Could not find hosted zone '[REDACTED]'
    at ServerlessCustomDomain.<anonymous> (/[REDACTED]/node_modules/serverless-domain-manager/dist/src/index.js:258:23)
    at Generator.throw (<anonymous>)
    at rejected (/[REDACTED]/node_modules/serverless-domain-manager/dist/src/index.js:6:65)
    at process.processTicksAndRejections (node:internal/process/task_queues:95:5)
```

**Domain Manager Configuration**
Replace this with your own `serverless.yml` file (anonymized, of course) to help us better resolve your issue.
```yaml
custom:
  customDomain:
    domainName: api.example.com
    createRoute53Record: true
```

**Versions**
- Domain Manager version(s): v7.3.1
- Node/npm version: Node 18
- Serverless Version: v3.38
- Lambda Code Javascript

**Possible Solution**
<!--- Only if you have suggestions on a fix for the bug -->

**Additional context/Screenshots**
