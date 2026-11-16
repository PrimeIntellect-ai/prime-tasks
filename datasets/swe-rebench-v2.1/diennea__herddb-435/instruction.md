Drop TABLE does not unload pages from the policy
In case of "DROP TABLE" we are not unloading all of the loaded pages and so the policy keeps references to them and it can potentially require an "unload".

This error has been reported in production (HerdDB Collections Framework, that uses a lot the DROP TABLE feature)


```
java.lang.RuntimeException: herddb.collections.CollectionsException: herddb.model.StatementExecutionException: herddb.storage.DataStorageManagerException: java.nio.file.NoSuchFileException: /xxxxxxxxtmp/swap/1d98e62e17d44834a7920f2db7dea569.tablespace/0a86b120-01ab-4cd0-9b8b-31d1a9a244ab.table/1.page
        at magnews.statsengine.proc.ProcEngine.lambda$scanHUserLogForClassicAccount$6(ProcEngine.java:3615)
        at magnews.statsengine.StatEngineDBConnection._visitNotifEventsFromSql(StatEngineDBConnection.java:7334)
        at magnews.statsengine.StatEngineDBConnection.visitNotifEvents(StatEngineDBConnection.java:7033)
        at magnews.statsengine.StatEngineDBConnection.visitNotifEvents(StatEngineDBConnection.java:6879)
        at magnews.statsengine.proc.ProcEngine.scanHUserLogForClassicAccount(ProcEngine.java:3611)
        at magnews.statsengine.proc.DailyAggregator.executeDailyAggregation(DailyAggregator.java:186)
        at magnews.statsengine.proc.DailyAggregator.work(DailyAggregator.java:98)
        at magnews.statsengine.proc.DailyAggregator.work(DailyAggregator.java:75)
        at magnews.statsengine.proc.DailyAggregator.run(DailyAggregator.java:231)
        at magnews.threads.locks.DistributedLockController.executeOnlyOnce(DistributedLockController.java:87)
        at magnews.statsengine.proc.DailyAggregatorTokenProcessor.process(DailyAggregatorTokenProcessor.java:52)
        at magnews.node.MajorodoTaskExecutorAdapter$LocalTaskExecutor.run(MajorodoTaskExecutorAdapter.java:167)
        at magnews.majorodo.worker.MajordodoWorkerService$TaskExecutorImpl.executeTask(MajordodoWorkerService.java:179)
        at majordodo.worker.ExecutorRunnable.run(ExecutorRunnable.java:59)
        at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
        at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
        at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
        at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
        at java.base/java.lang.Thread.run(Thread.java:835)
Caused by: java.lang.RuntimeException: herddb.collections.CollectionsException: herddb.model.StatementExecutionException: herddb.storage.DataStorageManagerException: java.nio.file.NoSuchFileException: /xxxxxxnode/tmp/swap/1d98e62e17d44834a7920f2db7dea569.tablespace/0a86b120-01ab-4cd0-9b8b-31d1a9a244ab.table/1.page
        at magnews.io.BoundedCollectionsManager$TmpMapWrapper.put(BoundedCollectionsManager.java:197)
        at magnews.statsengine.proc.ProcEngine$2.execute(ProcEngine.java:3604)
        at magnews.g0.util.BatchActionExecutor.execute(BatchActionExecutor.java:34)
        at magnews.statsengine.proc.ProcEngine.lambda$scanHUserLogForClassicAccount$6(ProcEngine.java:3613)
        ... 18 more
Caused by: herddb.collections.CollectionsException: herddb.model.StatementExecutionException: herddb.storage.DataStorageManagerException: java.nio.file.NoSuchFileException: /xxxx/mp/swap/1d98e62e17d44834a7920f2db7dea569.tablespace/0a86b120-01ab-4cd0-9b8b-31d1a9a244ab.table/1.page
        at herddb.collections.TmpMapImpl.put(TmpMapImpl.java:157)
        at magnews.io.BoundedCollectionsManager$TmpMapWrapper.put(BoundedCollectionsManager.java:194)
        ... 21 more
Caused by: herddb.model.StatementExecutionException: herddb.storage.DataStorageManagerException: java.nio.file.NoSuchFileException: /data/mn1/node/tmp/swap/1d98e62e17d44834a7920f2db7dea569.tablespace/0a86b120-01ab-4cd0-9b8b-31d1a9a244ab.table/1.page
        at herddb.core.TableSpaceManager.executeStatement(TableSpaceManager.java:1014)
        at herddb.collections.TmpMapImpl.put(TmpMapImpl.java:152)
        ... 22 more
Caused by: herddb.storage.DataStorageManagerException: java.nio.file.NoSuchFileException: /xxxxxxp/swap/1d98e62e17d44834a7920f2db7dea569.tablespace/0a86b120-01ab-4cd0-9b8b-31d1a9a244ab.table/1.page
        at herddb.file.FileDataStorageManager.writePage(FileDataStorageManager.java:889)
        at herddb.core.TableManager.flushNewPage(TableManager.java:914)
        at herddb.core.TableManager.flushNewPageForUnload(TableManager.java:792)
        at herddb.core.TableManager.lambda$unload$2(TableManager.java:714)
        at java.base/java.util.concurrent.ConcurrentHashMap.computeIfPresent(ConcurrentHashMap.java:1822)
        at herddb.core.TableManager.unload(TableManager.java:707)
        at herddb.core.TableManager.allocateLivePage(TableManager.java:633)
        at herddb.core.TableManager.applyInsert(TableManager.java:1948)
        at herddb.core.TableManager.apply(TableManager.java:1582)
        at herddb.core.TableManager.lambda$executeInsertAsync$4(TableManager.java:1101)
        at java.base/java.util.concurrent.CompletableFuture$UniApply.tryFire(CompletableFuture.java:642)
        at java.base/java.util.concurrent.CompletableFuture$Completion.run(CompletableFuture.java:478)
        at com.google.common.util.concurrent.MoreExecutors$DirectExecutorService.execute(MoreExecutors.java:261)
        at java.base/java.util.concurrent.CompletableFuture.uniApplyNow(CompletableFuture.java:677)
        at java.base/java.util.concurrent.CompletableFuture.uniApplyStage(CompletableFuture.java:658)
        at java.base/java.util.concurrent.CompletableFuture.thenApplyAsync(CompletableFuture.java:2175)
        at herddb.core.TableManager.executeInsertAsync(TableManager.java:1100)
        at herddb.core.TableManager.executeStatementAsync(TableManager.java:545)
        at herddb.core.TableSpaceManager.executeTableAwareStatement(TableSpaceManager.java:1176)
        at herddb.core.TableSpaceManager.executeStatementAsyncInternal(TableSpaceManager.java:1080)
        at herddb.core.TableSpaceManager.executeStatementAsync(TableSpaceManager.java:1060)
        at herddb.core.TableSpaceManager.executeStatement(TableSpaceManager.java:1003)
        ... 23 more
Caused by: java.nio.file.NoSuchFileException: /xxxxxxxtmp/swap/1d98e62e17d44834a7920f2db7dea569.tablespace/0a86b120-01ab-4cd0-9b8b-31d1a9a244ab.table/1.page
        at java.base/sun.nio.fs.UnixException.translateToIOException(UnixException.java:92)
        at java.base/sun.nio.fs.UnixException.rethrowAsIOException(UnixException.java:111)
        at java.base/sun.nio.fs.UnixException.rethrowAsIOException(UnixException.java:116)
        at java.base/sun.nio.fs.UnixFileSystemProvider.newFileChannel(UnixFileSystemProvider.java:182)
        at java.base/java.nio.channels.FileChannel.open(FileChannel.java:292)
        at java.base/java.nio.channels.FileChannel.open(FileChannel.java:345)
        at herddb.utils.ManagedFile.open(ManagedFile.java:78)
        at herddb.file.FileDataStorageManager.writePage(FileDataStorageManager.java:880)
        ... 44 more
```
