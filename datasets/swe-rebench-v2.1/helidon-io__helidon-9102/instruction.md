4.x - Mongo DbClientServiceContext futures not completed
## Environment Details
* Helidon Version: 4.0.11
* Helidon SE
----------

## Problem Description

When using MongoDbClient, both `statementFuture` and `resultFuture` (`io.helidon.dbclient.DbClientServiceContext`) are not completed.

## Steps to reproduce

```java
@Test
void testDbClientService() {
    CompletableFuture<Long> resultFuture = new CompletableFuture<>();
    CompletableFuture<Void> statementFuture = new CompletableFuture<>();
    DbClientService service = ctx -> {
        ctx.resultFuture().whenComplete((v, ex) -> {
            if (ex != null) {
                resultFuture.completeExceptionally(ex);
            } else {
                resultFuture.complete(v);
            }
        });
        ctx.statementFuture().whenComplete((v, ex) -> {
            if (ex != null) {
                statementFuture.completeExceptionally(ex);
            } else {
                statementFuture.complete(v);
            }
        });
        return ctx;
    };
    MongoDbClient dbClient = createClient(builder -> builder.addService(service));
    DbExecute exec = dbClient.execute();
    long ignored = exec.query("{\"operation\": \"command\", \"query\": { ping: 1 }}").count();
    assertThat(resultFuture.isDone(), is(true));
    assertThat(resultFuture.isCompletedExceptionally(), is(false));
    assertThat(statementFuture.isDone(), is(true));
    assertThat(statementFuture.isCompletedExceptionally(), is(false));
}
```

[//]: # "Step by step instructions to reproduce the problem"
[//]: # "Provide sample code/application if relevant"

### Additional contract requirements

- `io.helidon.dbclient.DbClientService` is a functional interface whose method is
  `DbClientServiceContext statement(DbClientServiceContext context)`; it is invoked for each
  statement executed by the client and returns the context.
- `io.helidon.dbclient.DbClientServiceContext` exposes `CompletionStage<Long> resultFuture()`
  and `CompletionStage<Void> statementFuture()`.
- `io.helidon.dbclient.mongodb.MongoDbClientBuilder` provides
  `MongoDbClientBuilder addService(DbClientService service)`.
- When a statement executed through `MongoDbClient` completes successfully, the context's
  `resultFuture` and `statementFuture` are completed.
