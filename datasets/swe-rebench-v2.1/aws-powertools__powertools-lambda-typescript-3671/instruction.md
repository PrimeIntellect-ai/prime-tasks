Bug: Incorrect data types for `sourceIPAddress` and `sequencer` Fields in S3RecordSchema Model
### Expected Behavior

When working with `S3 LifecycleTransition events`, the value of the `sourceIPAddress` field is `s3.amazonaws.com` instead of an IPv4 value. Additionally, the `sequencer` field is only populated on PUT and delete object events.

### Current Behavior

These fields are using incorrect data types.

### Code snippet

No code snippet.

### Steps to Reproduce

use this payload with this model.

```json
{
   "eventVersion":"2.3",
   "eventSource":"aws:s3",
   "awsRegion":"us-east-1",
   "eventTime":"2025-02-21T21:46:45.775Z",
   "eventName":"LifecycleTransition",
   "userIdentity":{
      "principalId":"s3.amazonaws.com"
   },
   "requestParameters":{
      "sourceIPAddress":"s3.amazonaws.com"
   },
   "responseElements":{
      "x-amz-request-id":"something-1",
      "x-amz-id-2":"something-2"
   },
   "s3":{
      "s3SchemaVersion":"1.0",
      "configurationId":"some-sns",
      "bucket":{
         "name":"bucket-name",
         "ownerIdentity":{
            "principalId":"PRICIPAL"
         },
         "arn":"arn:aws:s3:::bucket-name"
      },
      "object":{
         "key":"/path/to/file.parquet",
         "size":12345,
         "eTag":"abcdef1232423423",
         "versionId":"SomeThingThere"
      }
   },
   "lifecycleEventData":{
      "transitionEventData":{
         "destinationStorageClass":"INTELLIGENT_TIERING"
      }
   }
}
```

### Possible Solution

_No response_

### Powertools for AWS Lambda (TypeScript) version

latest

### AWS Lambda function runtime

22.x

### Packaging format used

npm

### Execution logs

```Shell

```

### Additional contract requirements

- The S3 event schema is exposed as `S3Schema` from `packages/parser/src/schemas/s3.ts`. Its `parse(event)` method validates a raw S3 event payload and returns the typed S3 event, throwing a parsing exception when the payload does not conform to the schema.
