Incorrect E3686 'AWS::RDS::DBCluster' ServerlessV2ScalingConfiguration exists if EngineMode is not set
### CloudFormation Lint Version

1.3.7

### What operating system are you using?

docker container based on python:3.12-alpine

### Describe the bug

```console
$ cfn-lint --template ./a.yaml
E3686 Additional properties are not allowed ('ServerlessV2ScalingConfiguration')
a.yaml:7:7
```


### Expected behavior

Do not report that that ServerlessV2ScalingConfiguration is not allowed.

Default EngineMode property value is "provisioned". So, if EngineMode is not set then error fof ScalingConfiguration property exists, but not error for ServerlessV2ScalingConfiguration property exists.

https://github.com/aws-cloudformation/cfn-lint/blob/3b782cbecf3073ae96ea33e202e4e2a4f15e3a4d/src/cfnlint/data/schemas/extensions/aws_rds_dbcluster/serverless_exclusive.json#L50

### Reproduction template

```yaml
Resources:
  AuroraClustor:
    Type: AWS::RDS::DBCluster
    Properties:
      Engine: aurora-postgresql
      EngineVersion: 14.6
      ServerlessV2ScalingConfiguration:
        MaxCapacity: 1
        MinCapacity: 1
```
