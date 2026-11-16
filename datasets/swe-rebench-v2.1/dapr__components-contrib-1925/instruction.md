aws sqs component can not support  China region such as cn-northwest-1
<!-- If you need to report a security issue please visit https://docs.dapr.io/operations/support/support-security-issues -->

## Expected Behavior

<!-- Briefly describe what you expect to happen -->
### I create  sqs component  and  set correct  sqs config info .
when  I pub message  by the component  ,I hope it work well ,but the daprd output error message as below.

## Actual Behavior

<!-- Briefly describe what is actually happening -->

![image](https://user-images.githubusercontent.com/38551720/180633118-9f2371f2-8825-4188-9657-2fe646765f82.png)


## Steps to Reproduce the Problem

<!-- How can a maintainer reproduce this issue (be detailed) -->

If I set  cn-northwest-1 to the region,   it will connect error，maybe cn-north-1 also have the same  problem。

[HIDDEN]

[HIDDEN]

 If region is  cn-*,the arn  should start with   arn:aws-cn

[HIDDEN]


![image](https://user-images.githubusercontent.com/38551720/180632668-371a9d7e-74e6-44ef-a241-d54178a68037.png)
snssqs.go
![image](https://user-images.githubusercontent.com/38551720/180632249-bf9c8f07-760f-418f-8a60-f32a3fe78d94.png)


## Release Note

<!-- How should the fix for this issue be communicated in our release notes? It can be populated later. -->
<!-- Keep it as a single line. Examples: -->

<!-- RELEASE NOTE: **ADD** New feature in Dapr. -->
<!-- RELEASE NOTE: **FIX** Bug in runtime. -->
<!-- RELEASE NOTE: **UPDATE** Runtime dependency. -->

RELEASE NOTE:

### Additional contract requirements

- Select the ARN partition based on the configured region, supporting AWS partitions rather than assuming every region uses the standard partition.
- ARN construction must retain the service identifier, configured region, account ID, and entity name in their respective ARN fields.
- Use `arn:aws:...` for standard regions such as `us-west-2`, `arn:aws-cn:...` for China regions such as `cn-northwest-1`, and `arn:aws-us-gov:...` for GovCloud regions such as `us-gov-west-1`.
