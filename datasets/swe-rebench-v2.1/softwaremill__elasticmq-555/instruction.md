1.3.0 docker image breaks custom elasticmq.conf
Following the readme, we essentially start a container with the following command:

```
docker run --rm -v `pwd`/elasticmq.conf:/opt/elasticmq.conf softwaremill/elasticmq
```

the elasticmq.conf file we pass in is:

```
include classpath("application.conf")

queues {
    void { }
}
```

In 1.3.0, this is the output (note the lack of acknowledgement of the queue being created)

```
16:42:14.157 [main] INFO  org.elasticmq.server.Main$ - Starting ElasticMQ server (1.3.0) ...
16:42:14.746 [elasticmq-akka.actor.default-dispatcher-4] INFO  akka.event.slf4j.Slf4jLogger - Slf4jLogger started
16:42:15.874 [elasticmq-akka.actor.default-dispatcher-4] INFO  o.e.rest.sqs.TheSQSRestServerBuilder - Started SQS rest server, bind address 0.0.0.0:9324, visible server address http://localhost:9324
16:42:16.028 [elasticmq-akka.actor.default-dispatcher-4] INFO  o.e.r.s.TheStatisticsRestServerBuilder - Started statistics rest server, bind address 0.0.0.0:9325
16:42:16.029 [main] INFO  org.elasticmq.server.Main$ - === ElasticMQ server (1.3.0) started in 2397 ms ===
```

If i run the following command to use 1.2.3 instead:

```
docker run --rm -v `pwd`/elasticmq.conf:/opt/elasticmq.conf softwaremill/elasticmq:1.2.3
```

The queue is made correctly:

```
16:42:39.347 [main] INFO  org.elasticmq.server.Main$ - Starting ElasticMQ server (1.2.3) ...
16:42:39.960 [elasticmq-akka.actor.default-dispatcher-5] INFO  akka.event.slf4j.Slf4jLogger - Slf4jLogger started
16:42:41.086 [elasticmq-akka.actor.default-dispatcher-7] INFO  o.e.rest.sqs.TheSQSRestServerBuilder - Started SQS rest server, bind address 0.0.0.0:9324, visible server address http://localhost:9324
16:42:41.218 [elasticmq-akka.actor.default-dispatcher-7] INFO  o.e.r.s.TheStatisticsRestServerBuilder - Started statistics rest server, bind address 0.0.0.0:9325
16:42:41.291 [elasticmq-akka.actor.default-dispatcher-7] INFO  o.elasticmq.actor.QueueManagerActor - Creating queue QueueData(void,MillisVisibilityTimeout(30000),PT0S,PT0S,2021-10-19T16:42:41.244Z,2021-10-19T16:42:41.244Z,None,false,false,None,None,Map())
16:42:41.328 [main] INFO  org.elasticmq.server.Main$ - === ElasticMQ server (1.2.3) started in 2499 ms ===
```

Looks like there's something in 1.3.0 that breaks this, and the Readme has not been updated on how to insert custom conf files (or this break was not intended?)

### Additional contract requirements

- Starting the server executable (`org.elasticmq.server.Main`) with a configuration file supplied through the `config.file` system property, where that file declares a queue under `queues`, must create that queue. Once the server is up, the queue must be listed by the SQS `ListQueues` action. This applies to any launch of the server with such a configuration file, not only to the Docker image.
