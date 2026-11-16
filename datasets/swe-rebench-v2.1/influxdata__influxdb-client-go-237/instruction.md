Retries are attempted even if MaxRetries is set to zero
<!--

Thank you for reporting a bug.

* Please add a :+1: or comment on a similar existing bug report instead of opening a new one.
    * https://github.com/influxdata/influxdb-client-go/issues?utf8=%E2%9C%93&q=is%3Aissue+is%3Aopen+is%3Aclosed+sort%3Aupdated-desc+label%3Abug+
* Please check whether the bug can be reproduced with the latest release.
* The fastest way to fix a bug is to open a Pull Request.
    * https://github.com/influxdata/influxdb-client-go/pulls

-->

__Steps to reproduce:__
Given the following client code snippet

```
	options := influxdb2.DefaultOptions().SetMaxRetries(0)
	client := influxdb2.NewClientWithOptions(url, authToken, options)
	defer client.Close()
	writeAPI := client.WriteAPIBlocking("", dbName)
        err := writeAPI.WritePoint(context.Background(), point)
        if err != nil {
            fmt.Printf("Error: %v", err)
        }
```

where `url` is the URL of an InfluxDB instance that is unreachable (i.e. results in a connection error), the `WritePoint()` method may attempt an implicit deferred retry (instead of immediately returning a connection error), even though MaxRetries was set to 0.

__Expected behavior:__
The `WritePoint()` method should always return an error in this case.

__Actual behavior:__
No error is returned.

__Specifications:__
 - Client Version: 2.2.2
 - InfluxDB Version: n/a (testing against an unreachable InfluxDB instance)
 - Platform: MacOS 10.15.7
