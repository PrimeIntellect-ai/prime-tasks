SQS `delete_message_batch` does not raise exception with no `Entries`
Hello,

When using `delete_message_batch` with an empty `Entries` parameter against AWS, the following exception is raised:
```
botocore.errorfactory.EmptyBatchRequest: An error occurred (AWS.SimpleQueueService.EmptyBatchRequest) when calling the DeleteMessageBatch operation: There should be at least one DeleteMessageBatchRequestEntry in the request.
```
But no exception is raised with moto

```python
with moto.mock_aws():
    sqs = boto3.client("sqs")
    queue = sqs.create_queue(QueueName="testing-queue")
    sqs.delete_message_batch(
        QueueUrl=queue["QueueUrl"],
        Entries=[],
    )
```

Tested with moto `5.0.13`
