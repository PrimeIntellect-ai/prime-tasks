Erlang Port Exhaustion
When sending metrics over UDP fails, `TelemetryMetricsStatsd` opens a fresh socket to send the metrics over. I'm assuming this is to handle some transient errors that are tied to that specific socket. However, the old socket is **not being closed** before the new one gets opened, resulting in port leakage and leading to an exhaustion of ports in the VM.

Combined with the Unix domain socket support I've implemented, and given the fact that `:gen_udp.send/4` returns an error if the Unix domain socket is not available, renders the following chart from our production systems last week, where port counts skyrocketed from 8k to 126k in a matter of minutes throughout our infrastructure (we were doing a rollout of the Datadog agent, which made the sockets unavailable for a moment):

![Screenshot_2020-07-20 Metric Explorer Datadog](https://user-images.githubusercontent.com/801356/87973218-772e1480-cac8-11ea-857e-e93098cb31ec.png)

To reproduce the issue:

1. Configure `TelemetryMetricsStatsd` with `socket_path` pointing to something that's _not_ a Unix domain socket.
2. Open `:observer`.
3. Send some metrics over.
4. Observe the port count increasing with each error logged.

The issue remains even when using regular UDP - it's just easier to reproduce with Unix domain sockets.

If I understand the socket re-opening correctly, we can close the old socket as soon as the new one is opened. I'll open a PR with a fix soon.
