Disable to restore persisted FIFO queue config
Hi

When using `queues-storage` config and creating FIFO queue, the queue is correctly created.
But when restarted, persisted queues does not be restored.

---

started with config
``` elasticmq.conf
include classpath("application.conf")

queues-storage {
  enabled = true
  path = "/data/queues.conf"
}
```
and created FIFO queue
```
aws sqs create-queue --queue-name dummy.fifo --attributes ReceiveMessageWaitTimeSeconds=20,FifoQueue=true --endpoint-url http://localhost:9324
```
then, file `/data/queues.conf` is created
```
queues {
 dummy.fifo {contentBasedDeduplication=false,copyTo="",defaultVisibilityTimeout=30000,delay=0,fifo=true,moveTo="",receiveMessageWait=0,tags{}}
}
```

In this config file, name includes `.fifo` suffix.
TypeSafe Config may read incorrectly as follows.
```
queues {
 dummy {
  fifo {contentBasedDeduplication=false,copyTo="",defaultVisibilityTimeout=30000,delay=0,fifo=true,moveTo="",receiveMessageWait=0,tags{}}
 }
}
```
