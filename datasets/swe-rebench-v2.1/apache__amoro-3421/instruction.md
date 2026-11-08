[Improvement]: [HIDDEN]
### Search before asking

- [x] I have searched in the [issues](https://github.com/apache/amoro/issues?q=is%3Aissue) and found no similar issues.


### What would you like to be improved?

When we execute a simple Spark insert SQL, the AMS side reported this error.

![Image](https://github.com/user-attachments/assets/cc519528-e513-4c07-9c7d-2d5413bbe969)

```
2025-01-20 18:01:40,998 ERROR [thrift-server-table-metastore-11] [org.apache.amoro.server.TableManagementService] [] - Thrift service:TableManagementService.renewBlocker execute failed
org.apache.amoro.server.exception.ObjectNotExistsException: Blocker 181 of hive_catalog.amoro_v7.block_test(tableId=874643) not exists
        at org.apache.amoro.server.table.TableRuntime.renew(TableRuntime.java:621) ~[amoro-ams-server-0.7.0.1-SNAPSHOT.jar:0.7.0.1-SNAPSHOT]
        at org.apache.amoro.server.table.DefaultTableService.renewBlocker(DefaultTableService.java:278) ~[amoro-ams-server-0.7.0.1-SNAPSHOT.jar:0.7.0.1-SNAPSHOT]
        at org.apache.amoro.server.TableManagementService.renewBlocker(TableManagementService.java:153) ~[amoro-ams-server-0.7.0.1-SNAPSHOT.jar:0.7.0.1-SNAPSHOT]
        at sun.reflect.NativeMethodAccessorImpl.invoke0(Native Method) ~[?:1.8.0_152]
        at sun.reflect.NativeMethodAccessorImpl.invoke(NativeMethodAccessorImpl.java:62) ~[?:1.8.0_152]
        at sun.reflect.DelegatingMethodAccessorImpl.invoke(DelegatingMethodAccessorImpl.java:43) ~[?:1.8.0_152]
        at java.lang.reflect.Method.invoke(Method.java:498) ~[?:1.8.0_152]
        at org.apache.amoro.server.utils.ThriftServiceProxy.invoke(ThriftServiceProxy.java:56) [amoro-ams-server-0.7.0.1-SNAPSHOT.jar:0.7.0.1-SNAPSHOT]
        at com.sun.proxy.$Proxy47.renewBlocker(Unknown Source) [?:?]
        at org.apache.amoro.api.AmoroTableMetastore$Processor$renewBlocker.getResult(AmoroTableMetastore.java:1635) [amoro-core-0.7.0.1-SNAPSHOT.jar:0.7.0.1-SNAPSHOT]
        at org.apache.amoro.api.AmoroTableMetastore$Processor$renewBlocker.getResult(AmoroTableMetastore.java:1611) [amoro-core-0.7.0.1-SNAPSHOT.jar:0.7.0.1-SNAPSHOT]
        at org.apache.amoro.shade.thrift.org.apache.thrift.ProcessFunction.process(ProcessFunction.java:40) [amoro-shade-thrift-0.20.0-0.7-SNAPSHOT.jar:0.20.0-0.7-SNAPSHOT]
        at org.apache.amoro.shade.thrift.org.apache.thrift.TBaseProcessor.process(TBaseProcessor.java:40) [amoro-shade-thrift-0.20.0-0.7-SNAPSHOT.jar:0.20.0-0.7-SNAPSHOT]
        at org.apache.amoro.shade.thrift.org.apache.thrift.TMultiplexedProcessor.process(TMultiplexedProcessor.java:147) [amoro-shade-thrift-0.20.0-0.7-SNAPSHOT.jar:0.20.0-0.7-SNAPSHOT]
        at org.apache.amoro.shade.thrift.org.apache.thrift.server.AbstractNonblockingServer$FrameBuffer.invoke(AbstractNonblockingServer.java:492) [amoro-shade-thrift-0.20.0-0.7-SNAPSHOT.jar:0.20.0-0.7-SNAPSHOT]
        at org.apache.amoro.shade.thrift.org.apache.thrift.server.Invocation.run(Invocation.java:19) [amoro-shade-thrift-0.20.0-0.7-SNAPSHOT.jar:0.20.0-0.7-SNAPSHOT]
        at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149) [?:1.8.0_152]
        at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624) [?:1.8.0_152]
        at java.lang.Thread.run(Thread.java:748) [?:1.8.0_152]
```

### How should we improve?

when we release the Renewableblocker, we should check whether we need to [HIDDEN]

![Image](https://github.com/user-attachments/assets/0784601c-eb58-419f-9e76-14ac8655924b)

### Are you willing to submit PR?

- [x] Yes I am willing to submit a PR!

### Subtasks

_No response_

### Code of Conduct

- [x] I agree to follow this project's [Code of Conduct](https://www.apache.org/foundation/policies/conduct)

### Additional contract requirements

- Releasing a RenewableBlocker must stop its periodic renewal.
