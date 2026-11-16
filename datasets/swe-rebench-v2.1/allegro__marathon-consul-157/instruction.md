Handle Mesos healthchecks
Mesos 1.1 introduces HTTP/S and TCP healthchecks. Marathon will support this healthchecks from 1.4. We need to support them too.

### Additional contract requirements

Mesos health-check protocol identifiers `MESOS_HTTP`, `MESOS_HTTPS`, and `MESOS_TCP` must be recognized when registering a task with Consul. They produce Consul HTTP, HTTPS, and TCP health checks respectively; HTTP and HTTPS checks use the configured health-check path, and all checks use the configured port.
