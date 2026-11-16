Add SlowConsumersStats to stats
### Proposed change

We added `SlowConsumersStats` to varz but a lot of our tooling such as `nats server report` and `nats server watch` are based on statz from `$SYS.REQ.SERVER.PING`.

Lets add `SlowConsumersStats` here also

### Use case

Improved tooling

### Contribution

_No response_

### Additional contract requirements

- The slow consumer statistics must be included in the `STATSZ` response returned for the stats ping subjects (`$SYS.REQ.SERVER.PING`, `$SYS.REQ.SERVER.PING.STATSZ`) and for the direct server request subject (`$SYS.REQ.SERVER.<id>.STATSZ`).
- In that response the statistics are exposed under the `slow_consumer_stats` JSON key, using the same field names as the existing varz `SlowConsumersStats` object: `clients`, `routes`, `gateways` and `leafs`.
