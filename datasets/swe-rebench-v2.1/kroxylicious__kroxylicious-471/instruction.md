kcat consumer terminates when kroxylicious is restarted despite the -E (Do not exit on non fatal error) flag
_Please use this to only for bug reports_. For questions or when you need help, you can use the [GitHub Discussions](https://github.com/kroxylicious/kroxylicious/discussions) or use the [community Slack](https://kroxylicious.slack.com) chat.

**Describe the bug**

Testing the work of #447,  I find that whilst a kcat producer is tolerate to a kroxylicios restart, a kcat consumer is not.
It tries to reconnect, but encounters this condition which it considers to be FATAL, and so exits.


```
% ERROR: Topic my-topic [0] error: my-topic [0]: desired partition is no longer available (Local: Unknown partition)
```

A clear and concise description of what the bug is.

**To Reproduce**
Steps to reproduce the behavior:
1. Setup with `./scripts/run-with-strimzi.sh kubernetes-examples/portperbroker_plain`
2. Run the kcat example commands (those being added by #469), but include the `-E` flag to the kcat command line.  Use kcat `1.6.0` so you can send messages from the producer one by one.
3. Send messages from consumer to producer iteratively.
4. `kubectl delete pod -n kafka kroxylicious-proxy..`
5. Observe that `kcat -P` tolerates the dropped connections, and reconnects.
6. Observe the `kcat -C` quits with the error above.

**Expected behavior**

Both `kcat -P -E` and `kcat -C -E` should reconnect and continue to allow producing and consuming of messages.

**YAML files and logs**

Attach or copy paste your kroxylicious configuration YAML (with sensitive details
like broker address redacted).
Attach or copy and paste relevant logs.

**Additional context**

The Java Kafka console producer and console consumer are resilient to kroxylicious restarts.

### Additional contract requirements

When a client sends a Metadata request, the proxy must pass that request on with fidelity, preserving the topics the client asked for, rather than substituting an empty request. This is what allows a client such as `kcat -C -E` to reconnect after a proxy restart and continue consuming.
