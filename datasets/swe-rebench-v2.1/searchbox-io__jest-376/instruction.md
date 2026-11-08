NPE In Node Discovery If Elasticsearch is Down
NodeChecker results in NPE if elasticsearch cluster is unavailable on the first run:

```
Caused by: java.lang.NullPointerException
    at io.searchbox.client.config.discovery.NodeChecker.removeNodeAndUpdateServers(NodeChecker.java:114)
    at io.searchbox.client.config.discovery.NodeChecker.runOneIteration(NodeChecker.java:70)
    at com.google.common.util.concurrent.AbstractScheduledService$ServiceDelegate$Task.run(AbstractScheduledService.java:189)
    at com.google.common.util.concurrent.Callables$3.run(Callables.java:100)
    at java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:511)
    at java.util.concurrent.FutureTask.runAndReset(FutureTask.java:308)
    at java.util.concurrent.ScheduledThreadPoolExecutor$ScheduledFutureTask.access$301(ScheduledThreadPoolExecutor.java:180)
    at java.util.concurrent.ScheduledThreadPoolExecutor$ScheduledFutureTask.run(ScheduledThreadPoolExecutor.java:294)
    at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1142)
    at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:617)
    at java.lang.Thread.run(Thread.java:745)
```
