`E3041` false positives
### CloudFormation Lint Version

1.3.3

### What operating system are you using?

Mac

### Describe the bug

I believe `E3041` is currently too strict: `Name` may be equal to `HostedZoneName`, i.e. when setting the root record.

### Expected behavior

Setting the DNS root record should pass validation.

### Reproduction template

I will create a PR including test cases.

### Additional contract requirements

- For invalid names, the validation error message must be `'<Name>' must be a subdomain of or equal to '<HostedZoneName>'`, with the actual values substituted.
