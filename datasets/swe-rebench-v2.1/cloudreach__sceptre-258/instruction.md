Remove response metadata output for validate-template
Currently the output of a successful vaildate-template command is something like:
```
Parameters:
- NoEcho: false
  ParameterKey: CommonSecurityGroupId
- NoEcho: false
  ParameterKey: SecurityGroupId
- NoEcho: false
  ParameterKey: IamInstanceProfile
- NoEcho: false
  ParameterKey: SubnetIds
ResponseMetadata:
  HTTPHeaders:
    content-length: '775'
    content-type: text/xml
    date: Thu, 23 Mar 2017 14:32:55 GMT
    x-amzn-requestid: 9ae7271b-0fd5-11e7-a1ea-2f8c8146f7d7
  HTTPStatusCode: 200
  RequestId: 9ae7271b-0fd5-11e7-a1ea-2f8c8146f7d7
  RetryAttempts: 0
```
Not sure there is a need for the `ResponseMetadata` - as it seems to only be information about the HTTP response from AWS - irrelevant to template validation.

### Additional contract requirements

- When `validate-template` succeeds and its response contains `Parameters: Example`, its output must be exactly `Template is valid. Template details:\n\nParameters: Example\n\n`.
