[BUG]: runtime.node.event_loop.delay.avg metric disappeared
### Tracer Version(s)

5.41.1

### Node.js Version(s)

v22.14.0

### Bug Report

Since the [v5.41.1](https://redirect.github.com/DataDog/dd-trace-js/compare/v5.41.0...v5.41.1), the metric `runtime.node.event_loop.delay.avg` disappeared from our dashboard.

The metrics comes back when we switch back to v5.41.0.

### Reproduction Code

* monitor a node process with dd-trace-js
* add `runtime.node.event_loop.delay.avg` metric to a dashboard
* with dd-trace-js v5.41.0, the metric is visible in the dashboard
* upgrade dd-trace-js to 5.41.1, the metric is no longer sent
* downgrade dd-trace-js to 5.41.0, the metric is sent again.

### Error Logs

_No response_

### Tracer Config

_No response_

### Operating System

_No response_

### Bundling

Unsure
