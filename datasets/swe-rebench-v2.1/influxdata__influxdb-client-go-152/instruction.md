Adding URL prefix to client
I'm currently trying to use this client to write to a VictoriaMetrics instance. They say that v2 API calls work correctly (https://victoriametrics.github.io/Cluster-VictoriaMetrics.html#url-format), but every time I try to write using this client, it appears the client is ignoring the prefix I set.

For example, if I set `http://localhost:8480/insert/0:0/influx` as my serverUrl, this client appears to use `http://localhost:8480/api/v2/write` instead of `http://localhost:8480/insert/0:0/influx/api/v2/write` as I would expect.

Am I doing something wrong in the client? My actual instantiation:

```
    client := influxdb2.NewClientWithOptions(
        fmt.Sprintf("http://%v:%v/insert/0:0/influx", hostname, port),
        "",
        influxdb2.DefaultOptions().SetBatchSize(BatchSize),
    )
    writeApi := client.WriteApi("", "telegraf")
```

The error I receive:

```
Jul 09 14:34:06 <> vminsert-prod[6281]: 2020-07-09T14:34:06.206Z        warn        VictoriaMetrics/lib/httpserver/httpserver.go:204        unsupported path requested: "/api/v2/write"
```

A similar error I received using the v1 client:

```root@<>:~# journalctl -xeu victoriametrics-vminsert | grep "write/write"
Jul 08 22:42:20 <> vminsert-prod[6281]: 2020-07-08T22:42:20.815Z        warn        VictoriaMetrics/lib/httpserver/httpserver.go:204        unsupported path requested: "/insert/0:0/influx/write/write"
```

In this case, we can see it used the full path I had defined:

```
c, err := client.NewHTTPClient(client.HTTPConfig{
                Addr: fmt.Sprintf("http://%v:%v/insert/0:0/influx/write", hostname, port),
        })
```

 Which leads me to believe the client is stripping any url prefix.
