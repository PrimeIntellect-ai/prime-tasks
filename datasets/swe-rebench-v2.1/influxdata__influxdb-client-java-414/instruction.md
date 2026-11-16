Problem Mapping Long fields
When It is mapped a Long (Not primitive) field on model class and we use pivot function to return the values for each field on model, a Cast exception is thrown during the execution.

It says is not possible cast Long to Double.
When we use long (primitive) it doesn't throw error, however it returns zero (not behavior expected).

__Steps to reproduce__:

1. Create a model with 2 fields:

ModelInflux.java
```
//use lombok

@Getter
@Setter
@Measurement(name="model2")
@ToString
public class ModelInflux {

   @Column
  private Long field1;
  @Column
  private Double field2;

  @Column(timestamp = true, name = "time")
  private Instant timestamp;

}

```
2. Save some data on InfluxDB
Main.java
```
  public static void save(ModelInflux object, InfluxDBClientReactive client) {
    WriteReactiveApi writeApi = client.getWriteReactiveApi();

    var publisher = writeApi.writeMeasurement(WritePrecision.NS, object);
    Disposable subscriber =
        Flowable.fromPublisher(publisher)
            .subscribe(success -> log.info("Successfully written ModelInflux measurement"));
    subscriber.dispose();
  }
```

3. Create a query with pivot function:
```
private static void runModelInflux(String host, String org, String token, String bucket)
      throws InterruptedException {

    String query = "from(bucket: \"test2\")"
        + "  |> range(start: -1h, stop: now())"
        + "  |> filter(fn: (r) => r[\"_measurement\"] == \"model2\")"
        + "  |> aggregateWindow(every: 10s, fn: mean, createEmpty: false)"
        + "  |> yield(name: \"mean\")"
        + "  |> pivot(rowKey:[\"_time\"], columnKey: [\"_field\"], valueColumn: \"_value\")";

    InfluxDBClientReactive client = InfluxDBClientReactiveFactory
        .create(host, token.toCharArray(), org, bucket);

    ModelInflux modelInflux = new ModelInflux();
    modelInflux.setField1((long)(Math.random() * 100));
    modelInflux.setField2((Math.random() * 100));

    save(modelInflux, client);

    Thread.sleep(1000);

    Instant end = Instant.now();
    Instant start = Instant.now().minus(1, ChronoUnit.HOURS);

    execute(query, client).doOnEach( e -> {
      if (e.get() != null) {
        log.info(e.get().toString());
      }
    }).doOnError(e -> {
      log.error(e.getMessage());
    }).subscribe();

    // Giving a time to process the result.
    Thread.sleep(10000);
  }
```
Main.java

```
  public static void main(String[] args) throws InterruptedException {
    String host = Main.HOST;
    String org = Main.ORG;
    String token= Main.TOKEN;
    String bucket = Main.BUCKET;

    runModelInflux2(host, org, token, "test2");
  }
```


__Expected Behavior__:

Return the model without error and value available.

__Actual Behavior__:
Error:
Caused by: com.influxdb.exceptions.InfluxException: Can not set java.lang.Long field com.autonomic.test.domain.ModelInflux2.field1 to java.lang.Double

__Specifications:__
 - Client Version: 6.4.0
 - InfluxDB Version: 2.0.9
 - JDK Version: Corretto 11.0.15.9.1
 - Platform: Mac OS M1

PS.: I see this code is converting only to primitives. (Maybe include more options to conversion?)
https://github.com/influxdata/influxdb-client-java/blob/f9f6aa0429977525ffaef4f745ab1f7958623cb1/client-core/src/main/java/com/influxdb/query/internal/FluxResultMapper.java#L132-L144
