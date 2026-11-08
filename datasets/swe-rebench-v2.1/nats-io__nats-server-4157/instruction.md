Allow sorting Connz by RTT
It would be nice to be able to sort `Connz` results by their RTT descending, as filtering on larger numbers of connections makes it hard to discover connections that have a high RTT to the server.

### Additional contract requirements

- `Connz` results can be sorted by round-trip time (RTT) in descending order.
- The sort is selected by setting `ConnzOptions.Sort` to the value `"rtt"`.
- The same sort is selectable through the monitoring endpoint query parameter
  `sort=rtt` (for example `/connz?sort=rtt`).
- When sorted by RTT, the returned connections are ordered from the highest RTT
  to the lowest RTT, as reported by the `RTT` field of each `ConnInfo`.
