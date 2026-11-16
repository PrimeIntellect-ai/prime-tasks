Pass key-value tags as objects
To my understanding, the StatsD implementations with tag support expect the tags to be key-value pairs. Hot-shots expects users to do the formatting, which is not ideal. Users must also do sanitation of tags which is even less ideal.

Instead, there could be automatic formatting of key-value tags to array

```javascript
statsd.increment("metric", 1, { "key": "value" });
```

should be the same as

```javascript
statsd.increment("metric", 1, ["key:value"]);
```

The implementation could be backwards compatible. If tags is passed as an array, no formatting would be performed.

[InfluxDB](https://www.influxdata.com/blog/getting-started-with-sending-statsd-metrics-to-telegraf-influxdb/) and [Datadog Statsd](http://docs.datadoghq.com/guides/dogstatsd/) use different format for tags. This annoying, but could be addressed by a configuration option.

I've created [a wrapper](https://github.com/lautis/hot-shots-deux) for hot-shots that implements the tagging for the Datadog format. Would you be interested in having this functionality in hot-shots? I'd be happy to make a PR out of this.

### Additional contract requirements

- In object-form tags, replace commas, colons, and at-signs in tag keys and values with underscores before formatting them.
