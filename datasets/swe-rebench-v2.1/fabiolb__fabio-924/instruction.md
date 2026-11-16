Fabio is using Datadog reserved tag keys
Some metrics are sent with tags `service`, `host`, `path`, `target`:

https://github.com/fabiolb/fabio/blob/642e425cf664e23d257ca357b7b1bfd1e432683d/route/route.go#L64-L66

But `service` and `host` are [reserved tag keys in Datadog](https://docs.datadoghq.com/getting_started/tagging/#overview)

According to [Host tag](https://docs.datadoghq.com/metrics/custom_metrics/dogstatsd_metrics_submission/#host-tag)
> The host tag is assigned automatically by the Datadog Agent aggregating the metrics. Metrics submitted with a host tag not matching the Agent hostname lose reference to the original host. The submitted host tag overrides any hostname collected by or configured in the Agent.

and https://github.com/DataDog/datadog-agent/issues/6245, these metric loose any configuration in the datadog-agent. In our case it is the `env` tag that is being lost.

It can be tested with:
```
echo -n "custom.metric.nameA:1|c|#host:foo" |nc -vu -w1 localhost 8125
```
![image](https://user-images.githubusercontent.com/8249379/217234290-b532c511-ae65-46ea-ab30-900c429c7cb5.png)

```
echo -n "custom.metric.nameB:1|c|#host1:foo" |nc -vu -w1 localhost 8125
```
![Screenshot 2023-02-07 at 11-35-13 Metrics Summary Datadog2](https://user-images.githubusercontent.com/8249379/217234591-8f901560-6b48-49fa-953f-4395faa0fab6.png)

### Additional contract requirements

- For DogStatsD metrics, emit the `service` tag key as `fabio-service` and the `host` tag key as `fabio-host`, preserving their tag values.
