Is IPv6 supported?
It seems like [HIDDEN] to enable support for IPv6.   If so, and if I'm reading the [UDP module](https://github.com/beam-telemetry/telemetry_metrics_statsd/blob/6f0df1e21fbb68df05f8040f9d85c0e1c0a05c47/lib/telemetry_metrics_statsd/udp.ex) right, that's not currently possible.

Does that all seem right to you?  I could potentially make a PR for this, but I wanted to sanity check first 😄

### Additional contract requirements

The reporter must be able to send StatsD metrics to an IPv6 UDP destination. Configure the address family with the `:inet_address_family` option set to `:inet6`, and provide the destination in the existing `:host` option.
