A Record (Alias) not being created
<!--- Please keep this note for the community --->

### Community Note

* Please vote on this issue by adding a 👍 [reaction](https://blog.github.com/2016-03-10-add-reactions-to-pull-requests-issues-and-comments/) to the original issue to help the community and maintainers prioritize this request
* Please do not leave "+1" or "me too" comments, they generate extra noise for issue followers and do not help prioritize the request
* If you are interested in working on this issue or have submitted a pull request, please leave a comment

<!--- Thank you for keeping this note for the community --->

## Bug Report

**Error Description**
The custom domain is created and mapped to my API Gateway but the needed A Record in Route 53 is not being created.


**Command Run**
`sls deploy`

**Console Output**
No errors reported

**Domain Manager Configuration**
Replace this with your own `serverless.yml` file (anonymized, of course) to help us better resolve your issue.
```yaml
customDomain:
    domainName: my-domain.com
    stage: ${self:provider.stage}
    apiType: rest
    basePath: v1
    certificateName: my-cert
    createRoute53Record: true
    endpointType: regional
```

**Versions**
- Domain Manager version(s): 4.1.1
- Node/npm version: Node 12
- Serverless Version: 1.73.1
- Lambda Code JavaScript

**Possible Solution**
<!--- Only if you have suggestions on a fix for the bug -->

**Additional context/Screenshots**
Add any other context about the problem here. If applicable, add screenshots to help explain.

### Additional contract requirements

- For an existing domain named `test_domain`, after logging `Custom domain test_domain already exists.`, the next console output must contain `Custom domain test_domain was created.`
