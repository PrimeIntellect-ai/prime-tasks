Autocannon sends two extra bytes at the end of the body, breaking the protocol
I've tested [uWS](https://github.com/uNetworking/uWebSockets.js) HTTP server and passed little body in every http request. It produced strange results.
I asked (https://github.com/uNetworking/uWebSockets.js/issues/228) creator of uWS why it happens and he researched what _"autocannon sends two extra bytes at the end of the body, breaking the protocol.  uWebSockets does not close the connection immediately, as it has a different parsing strategy. "_

Can you fix it, please?

```
$ autocannon -c 100 -p 100 -d 10 -m POST -b '{"a":1}' http://0.0.0.0:8080
Running 10s test @ http://0.0.0.0:8080
100 connections with 100 pipelining factor

┌─────────┬──────┬──────┬───────┬───────┬──────────┬──────────┬────────────┐
│ Stat    │ 2.5% │ 50%  │ 97.5% │ 99%   │ Avg      │ Stdev    │ Max        │
├─────────┼──────┼──────┼───────┼───────┼──────────┼──────────┼────────────┤
│ Latency │ 0 ms │ 0 ms │ 56 ms │ 82 ms │ 13.01 ms │ 34.33 ms │ 3618.88 ms │
└─────────┴──────┴──────┴───────┴───────┴──────────┴──────────┴────────────┘
┌───────────┬─────┬──────┬────────┬────────┬────────┬─────────┬─────────┐
│ Stat      │ 1%  │ 2.5% │ 50%    │ 97.5%  │ Avg    │ Stdev   │ Min     │
├───────────┼─────┼──────┼────────┼────────┼────────┼─────────┼─────────┤
│ Req/Sec   │ 0   │ 0    │ 1253   │ 3683   │ 1655.6 │ 1489.25 │ 26      │
├───────────┼─────┼──────┼────────┼────────┼────────┼─────────┼─────────┤
│ Bytes/Sec │ 0 B │ 0 B  │ 231 kB │ 678 kB │ 305 kB │ 274 kB  │ 4.78 kB │
└───────────┴─────┴──────┴────────┴────────┴────────┴─────────┴─────────┘

Req/Bytes counts sampled once per second.

17k requests in 10.15s, 3.05 MB read
7k errors (0 timeouts)
```
