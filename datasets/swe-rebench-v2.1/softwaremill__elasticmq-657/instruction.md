[BUG] Message Persistence: Deleted dead letter queue messages are recovered after docker container restart
Expected:
---
GIVEN message persistence is enabled
AND a message moved to a dead letter queue is manually deleted
I EXPECT that a message deleted from the dead letter queue will not be restored after the docker container restarts

Actual:
---
Messages previously deleted from a dead letter queue are restored after `docker restart myelasticmqinstance`


To reproduce:
---
- elasticmq.conf
```
include classpath("application.conf")

# What is the outside visible address of this ElasticMQ node
# Used to create the queue URL (may be different from bind address!)
node-address {
  protocol = http
  host = localhost
  port = 9324
  context-path = ""
}

rest-sqs {
  enabled = true
  bind-port = 9324
  bind-hostname = "0.0.0.0"
  # Possible values: relaxed, strict
  sqs-limits = strict
}

rest-stats {
  enabled = true
  bind-port = 9325
  bind-hostname = "0.0.0.0"
}

# Should the node-address be generated from the bind port/hostname
# Set this to true e.g. when assigning port automatically by using port 0.
generate-node-address = false

queues {
  myqueue {
    defaultVisibilityTimeout = 1 seconds
    delay = 5 seconds
    receiveMessageWait = 0 seconds
    deadLettersQueue {
      name = "myqueue-dead-letters"
      maxReceiveCount = 1 // from 1 to 1000
    }
    contentBasedDeduplication = true
    tags {
      tag1 = "tagged1"
      tag2 = "tagged2"
    }
  }
  myqueue-dead-letters { }
}

queues-storage {
  enabled = true
}

messages-storage {
  enabled = true
}

# Region and accountId which will be included in resource ids
aws {
  region = us-west-2
  accountId = 000000000000
}
```

- Run elasticmq via docker
```
docker run --name myelasticmqinstance  -p 9324:9324 -p 9325:9325 -v `pwd`/conf/elasticmq.conf:/opt/elasticmq.conf -v `pwd`/data:/data softwaremill/elasticmq-native
```

- Send a message to `myqueue`
```
aws --endpoint-url http://localhost:9324 sqs send-message --queue-url http://localhost:9324/queue/myqueue --message-body "Hello, queue!"
```

- View message in `myqueue` twice using command below twice
```
aws --endpoint-url http://localhost:9324 sqs receive-message --queue-url http://localhost:9324/queue/myqueue
```

- Copy the message receipt handle
- Observe the message go to the dead letter queue (`http://localhost:9325`) after 2 views, given config above

- Manually delete the message from `myqueue-dead-letters` queue using the receipt handle saved in previous step
```
aws --endpoint-url http://localhost:9324 sqs delete-message --queue-url http://localhost:9324/queue/myqueue-dead-letters --receipt-handle XYZ...
```

- Stop the docker instance
- Start the docker instance
- View the message queue contents `http://localhost:9325`; observe the deleted message has been restored
