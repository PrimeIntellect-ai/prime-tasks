need to set serviceMapping in dd-trace.init()
when java services call mysql and redis, In datadog APM it is shown correctly as `java-service -> mysql`, `java-service -> redis`, but when one nodeJS service is calling redis or mysql it gets named as `NodeJSservice -> NodeJSservice-mysql` and `NodeJSservice -> NodeJSservice-redis`, it gets prefixed with servicename. upon checking on it i came to know that we have to set `serviceMapping`.

We are using `ioredis` and `mysql2` libraries.

```
require('dd-trace').init({
    env: ENV
    service: 'SERVICE',
    version: VERSION,
    logInjection: true,
    serviceMapping: 'mysql2:abc-mysql,ioredis:abc-redis',
    profiling: true,
  });
```
It still shows as NodeJSservice-redis & NodeJSservice-mysql in datadog

what am i doing wrong?

dd-trace-js version 3.9.3

### Additional contract requirements

A caller can pass `serviceMapping: { <integration name>: <service name> }` to tracer initialization. The mapping applies to plugin-created spans, which report the configured service name for the mapped integration.
