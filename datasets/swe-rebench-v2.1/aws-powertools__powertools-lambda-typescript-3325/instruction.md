Bug: KafkaSelfManagedEventModel eventSource not correct
### Expected Behavior

Original issue: https://github.com/aws-powertools/powertools-lambda-python/issues/5559

[HIDDEN]

Reference: https://docs.aws.amazon.com/lambda/latest/dg/with-kafka.html

### Current Behavior

Trying to validate with `aws:SelfManagedKafka` fails.

### Code snippet

No code snippet

### Steps to Reproduce

Use this event to validate

```json
{
   "eventSource": "SelfManagedKafka",
   "bootstrapServers":"b-2.demo-cluster-1.a1bcde.c1.kafka.us-east-1.amazonaws.com:9092,b-1.demo-cluster-1.a1bcde.c1.kafka.us-east-1.amazonaws.com:9092",
   "records":{
      "mytopic-0":[
         {
            "topic":"mytopic",
            "partition":0,
            "offset":15,
            "timestamp":1545084650987,
            "timestampType":"CREATE_TIME",
            "key":"abcDEFghiJKLmnoPQRstuVWXyz1234==",
            "value":"SGVsbG8sIHRoaXMgaXMgYSB0ZXN0Lg==",
            "headers":[
               {
                  "headerKey":[
                     104,
                     101,
                     97,
                     100,
                     101,
                     114,
                     86,
                     97,
                     108,
                     117,
                     101
                  ]
               }
            ]
         }
      ]
   }
}
```

### Possible Solution

_No response_

### Powertools for AWS Lambda (TypeScript) version

latest

### AWS Lambda function runtime

20.x

### Packaging format used

npm, Lambda Layers

### Execution logs

```Shell

```

### Additional contract requirements

- Self-managed Kafka event validation must accept an event whose `eventSource` is `SelfManagedKafka`.
