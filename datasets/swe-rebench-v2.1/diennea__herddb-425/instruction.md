Divide by zero on new page flush
Bug report.

I got a divide by zero during a new page flush.

```
java.sql.SQLException: java.util.concurrent.CompletionException: java.lang.ArithmeticException: / by zero
        at java.base/java.util.concurrent.CompletableFuture.encodeThrowable(CompletableFuture.java:314)
        at java.base/java.util.concurrent.CompletableFuture.completeThrowable(CompletableFuture.java:319)
        at java.base/java.util.concurrent.CompletableFuture$UniApply.tryFire(CompletableFuture.java:645)
        at java.base/java.util.concurrent.CompletableFuture$Completion.run(CompletableFuture.java:478)
        at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
        at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
        at io.netty.util.concurrent.FastThreadLocalRunnable.run(FastThreadLocalRunnable.java:30)
        at java.base/java.lang.Thread.run(Thread.java:834)
Caused by: java.lang.ArithmeticException: / by zero
        at herddb.core.PageSet$DataPageMetaData.<init>(PageSet.java:58)
        at herddb.core.PageSet.pageCreated(PageSet.java:139)
        at herddb.core.TableManager.flushNewPage(TableManager.java:815)
        at herddb.core.TableManager.flushNewPageForUnload(TableManager.java:763)
        at herddb.core.TableManager.lambda$unload$2(TableManager.java:711)
        at java.base/java.util.concurrent.ConcurrentHashMap.computeIfPresent(ConcurrentHashMap.java:1822)
        at herddb.core.TableManager.unload(TableManager.java:704)
        at herddb.core.TableManager.allocateLivePage(TableManager.java:630)
        at herddb.core.TableManager.applyUpdate(TableManager.java:1728)
        at herddb.core.TableManager.onTransactionCommit(TableManager.java:1413)
        at herddb.core.TableSpaceManager.apply(TableSpaceManager.java:361)
        at herddb.core.TableSpaceManager.lambda$commitTransaction$16(TableSpaceManager.java:1692)
        at java.base/java.util.concurrent.CompletableFuture$UniApply.tryFire(CompletableFuture.java:642)
        ... 5 more
```

It occurred on a fresh standalone installation of HerdDB.
