[Bug]: Global Catalog configuration not valid for table build check
### What happened?

![image](https://github.com/NetEase/arctic/assets/109209550/bd86789d-e7b4-4a1c-8329-9efcbd7dbe46)
![image](https://github.com/NetEase/arctic/assets/109209550/ad30e9e3-8b92-4748-a988-ba1b56216807)
As you can see, after I configured table.log-store.topic = xxxxx in the global configuration of catalog, I still get an error saying that this configuration cannot be null.

### Affects Versions

0.4.x

### What engines are you seeing the problem on?

Core

### How to reproduce

1.Create a catalog and set properties log-store.topic = xxxxx
2.Create a table under this catalog and set properties log-store.enabled = true

### Relevant log output

```shell
2023/06/12 20:12:10 java.lang.IllegalArgumentException: log-store.topic must not be null when log-store.enabled is true.
	at org.apache.iceberg.relocated.com.google.common.base.Preconditions.checkArgument(Preconditions.java:142)
	at com.netease.arctic.catalog.BasicArcticCatalog$ArcticTableBuilder.checkProperties(BasicArcticCatalog.java:549)
	at com.netease.arctic.catalog.BasicArcticCatalog$ArcticTableBuilder.doCreateCheck(BasicArcticCatalog.java:539)
	at com.netease.arctic.hive.catalog.ArcticHiveCatalog$ArcticHiveTableBuilder.doCreateCheck(ArcticHiveCatalog.java:249)
	at com.netease.arctic.catalog.BasicArcticCatalog$ArcticTableBuilder.create(BasicArcticCatalog.java:488)
	at com.netease.arctic.spark.ArcticSparkCatalog.createTable(ArcticSparkCatalog.java:198)
	at org.apache.spark.sql.execution.datasources.v2.CreateTableExec.run(CreateTableExec.scala:41)
	at org.apache.spark.sql.execution.datasources.v2.V2CommandExec.result$lzycompute(V2CommandExec.scala:40)
	at org.apache.spark.sql.execution.datasources.v2.V2CommandExec.result(V2CommandExec.scala:40)
	at org.apache.spark.sql.execution.datasources.v2.V2CommandExec.executeCollect(V2CommandExec.scala:46)
	at org.apache.spark.sql.Dataset.$anonfun$logicalPlan$1(Dataset.scala:228)
	at org.apache.spark.sql.Dataset.$anonfun$withAction$1(Dataset.scala:3687)
	at org.apache.spark.sql.execution.SQLExecution$.$anonfun$withNewExecutionId$5(SQLExecution.scala:103)
	at org.apache.spark.sql.execution.SQLExecution$.withSQLConfPropagated(SQLExecution.scala:163)
	at org.apache.spark.sql.execution.SQLExecution$.$anonfun$withNewExecutionId$1(SQLExecution.scala:90)
	at org.apache.spark.sql.SparkSession.withActive(SparkSession.scala:772)
	at org.apache.spark.sql.execution.SQLExecution$.withNewExecutionId(SQLExecution.scala:64)
	at org.apache.spark.sql.Dataset.withAction(Dataset.scala:3685)
	at org.apache.spark.sql.Dataset.(Dataset.scala:228)
	at org.apache.spark.sql.Dataset$.$anonfun$ofRows$2(Dataset.scala:99)
	at org.apache.spark.sql.SparkSession.withActive(SparkSession.scala:772)
	at org.apache.spark.sql.Dataset$.ofRows(Dataset.scala:96)
	at org.apache.spark.sql.SparkSession.$anonfun$sql$1(SparkSession.scala:615)
	at org.apache.spark.sql.SparkSession.withActive(SparkSession.scala:772)
	at org.apache.spark.sql.SparkSession.sql(SparkSession.scala:610)
	at com.netease.arctic.ams.server.terminal.local.LocalTerminalSession.executeStatement(LocalTerminalSession.java:65)
	at com.netease.arctic.ams.server.terminal.TerminalSessionContext$ExecutionTask.executeStatement(TerminalSessionContext.java:275)
	at com.netease.arctic.ams.server.terminal.TerminalSessionContext$ExecutionTask.execute(TerminalSessionContext.java:238)
	at com.netease.arctic.ams.server.terminal.TerminalSessionContext$ExecutionTask.lambda$get$0(TerminalSessionContext.java:199)
	at com.netease.arctic.table.TableMetaStore.doAsUgi(TableMetaStore.java:365)
	at com.netease.arctic.table.TableMetaStore.lambda$doAs$0(TableMetaStore.java:345)
	at java.security.AccessController.doPrivileged(Native Method)
	at javax.security.auth.Subject.doAs(Subject.java:360)
	at org.apache.hadoop.security.UserGroupInformation.doAs(UserGroupInformation.java:1873)
	at com.netease.arctic.table.TableMetaStore.doAs(TableMetaStore.java:345)
	at com.netease.arctic.ams.server.terminal.TerminalSessionContext$ExecutionTask.get(TerminalSessionContext.java:191)
	at com.netease.arctic.ams.server.terminal.TerminalSessionContext$ExecutionTask.get(TerminalSessionContext.java:162)
	at java.util.concurrent.CompletableFuture$AsyncSupply.run(CompletableFuture.java:1604)
	at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
	at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
	at java.lang.Thread.run(Thread.java:748)
```


### Anything else

_No response_

### Code of Conduct

- [X] I agree to follow this project's Code of Conduct

### Additional contract requirements

- When a catalog has `log-store.topic` configured and a table under that catalog sets `log-store.enabled = true` without specifying its own topic, the catalog-level topic must be honored so table creation does not fail because `log-store.topic` is null.
