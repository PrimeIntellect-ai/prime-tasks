doctl apps logs doesn't output JSON
**What is the problem this feature would solve? Please describe.**

On our apps services, we use JSON logging (pino) and it'd be really helpful to be able to do `doctl apps logs <id> -f | pino-pretty` but I can't because the log lines include the service name and the log timestamp, not just the log message:

```
webapp 2024-05-29T20:14:14.996999111Z {"level":30,"time":1717013654993,  ....
```

**Describe the solution you'd like**

I'd like to just get what I logged, i.e., the JSON, without the `webapp 2024-05-29T20:14:14.996999111Z ` prefix.

**Additional context**

This would greatly improve my experience debugging apps on DO's App platform (currently we use papertrail, but it's not a particularly good log querier (doesn't parse the log lines correctly)

### Additional contract requirements

The `doctl apps logs` command must provide a `--no-prefix` option that emits each logged payload without the service name and timestamp prefix.
