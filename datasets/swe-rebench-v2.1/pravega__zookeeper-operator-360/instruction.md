Add support for more zoo.cfg configuration parameters
### Description

In our environment we are looking into tweaking `clientPortListenBacklog` and `serverCnxnFactory` zoo.cfg parameters to tune the zookeeper server(s) listening sockets.

### Importance

Should-have


### Suggestions for an improvement

we could extend the existing support to add these parameters.

### Additional contract requirements

- `spec.config.additionalConfig` is a map of custom zoo.cfg parameters, mapping string keys to string values.
- Every entry in `additionalConfig` is emitted into the generated `zoo.cfg` as a line of the exact form `<key>=<value>` followed by a newline.
- This `additionalConfig` mechanism is how the requested `clientPortListenBacklog` and `serverCnxnFactory` parameters are supported: setting `additionalConfig: {clientPortListenBacklog: "100"}` must produce a `clientPortListenBacklog=100` line in `zoo.cfg`, and setting `additionalConfig: {serverCnxnFactory: "org.apache.zookeeper.server.NettyServerCnxnFactory"}` must produce a `serverCnxnFactory=org.apache.zookeeper.server.NettyServerCnxnFactory` line in `zoo.cfg`.
- `ZookeeperConfig.DeepCopy()` must recreate the `AdditionalConfig` map so that mutating the copy's map does not affect the original.
