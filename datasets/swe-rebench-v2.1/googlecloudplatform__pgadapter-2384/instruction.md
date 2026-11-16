OpenTelemetry Cardinality Errors and ResourceExhaustedException
<!--- Provide a general summary of the issue in the Title above -->

## Current Behavior
Receiving multiple rounds of error messages below:
```
[2024-09-24 09:24:05.576] [WARNING] (io.opentelemetry.sdk.internal.ThrottlingLogger doLog): Instrument spanner/pgadapter/client_lib_latencies has exceeded the maximum allowed cardinality (1999).

[2024-09-24 09:24:05.577] [WARNING] (io.opentelemetry.sdk.internal.ThrottlingLogger doLog): Instrument spanner/pgadapter/roundtrip_latencies has exceeded the maximum allowed cardinality (1999).

[2024-09-24 09:24:17.173] [WARNING] (io.opentelemetry.sdk.metrics.export.PeriodicMetricReader$Scheduled doRun): Exporter threw an Exception

com.google.api.gax.rpc.ResourceExhaustedException: io.grpc.StatusRuntimeException: RESOURCE_EXHAUSTED: One or more TimeSeries could not be written: Monitored resource has too many time series (workload metrics).: generic_node{location:global,namespace:,node_id:} timeSeries[0-199]: workload.googleapis.com/spanner/pgadapter/roundtrip_latencies{project_id:<REDACTED>,database:<REDACTED>,instrumentation_source:cloud.google.com/java,instrumentation_version:,pgadapter_connection_id:9692880b-d1d1-467e-bb27-f7bc4243f9f0,service_name:pgadapter-66900913,instance_id:<REDACTED>}
	at com.google.api.gax.rpc.ApiExceptionFactory.createException(ApiExceptionFactory.java:100)
	at com.google.api.gax.grpc.GrpcApiExceptionFactory.create(GrpcApiExceptionFactory.java:98)
	at com.google.api.gax.grpc.GrpcApiExceptionFactory.create(GrpcApiExceptionFactory.java:66)
	at com.google.api.gax.grpc.GrpcExceptionCallable$ExceptionTransformingFuture.onFailure(GrpcExceptionCallable.java:97)
	at com.google.api.core.ApiFutures$1.onFailure(ApiFutures.java:84)
	at com.google.common.util.concurrent.Futures$CallbackListener.run(Futures.java:1130)
	at com.google.common.util.concurrent.DirectExecutor.execute(DirectExecutor.java:31)
```

- Errors seem to occur across all pods
- Cardinality errors are emitted after ~55 minutes of uptime and repeat every 12 seconds thereafter on each pod
- `RESOURCE_EXHAUSTED` exceptions start emitting after 1 minute of uptime and tend to repeat every minute thereafter on each pod
- On `RESOURCE_EXHAUSTED` exceptions within a single PGAdapter instance, `pgadapter_connection_id` tends to change over time

## Context (Environment)

- Running PGAdapter 0.39.0 as a sidecar in GKE
- 72 Pods in the Deployment
- PGAdapter configured with 1 vCPU and 2GB Memory limits (actual CPU use hovers at ~ 100mCPU)
- PGAdapter executed with the following args:
```
- args:
  - -p
  - <REDACTED>
  - -i
  - <REDACTED>
  - -d
  - <REDACTED>
  - -enable_otel
  - -otel_trace_ratio=0.05
  - -enable_otel_metrics
```

## Other Information
I poked around Metrics Explorer to see if there was anything out of the ordinary. When looking at both `workload.googleapis.com/spanner/pgadapter/roundtrip_latencies` and `workload.googleapis.com/spanner/pgadapter/client_lib_latencies` over the last 3 hours, then changing the aggregation to counting time series, it produces a value of 162,745 which seems like a lot of time series.

I inspected another distribution type metric, `spanner.googleapis.com/transaction_stat/total/transaction_latencies`, and it produced a value of 1.

I'm not sure if the difference here is a problem, but thought it was interesting enough to mention.

### Additional contract requirements

- Metric time series emitted for PGAdapter must not be distinguished by a per-connection identifier. Two connections to the same Spanner database must produce identical metric attributes, so the number of metric time series does not grow with the number of connections.
