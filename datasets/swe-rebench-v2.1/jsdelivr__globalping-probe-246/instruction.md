Wrong totals in case of error
```
{
  "probe": {
    "continent": "EU",
    "region": "Western Europe",
    "country": "DE",
    "state": null,
    "city": "Nuremberg",
    "asn": 200249,
    "longitude": 11.06833,
    "latitude": 49.44778,
    "network": "Products Up GmbH",
    "tags": [
      "eyeball-network"
    ],
    "resolvers": [
      "private",
      "private",
      "private"
    ]
  },
  "result":{
    "status":"finished",
    "rawOutput":"PING  (104.18.186.31) 56(84) bytes of data.\nFrom eth2-1109-fsn-lf-e03.productsup.int (10.254.254.17) icmp_seq=1 Destination Port Unreachable\n\n---  ping statistics ---\n1 packets transmitted, 0 received, +1 errors, 100% packet loss, time 0ms\n",
    "resolvedAddress":"104.18.186.31",
    "resolvedHostname":null,
    "timings":[

    ],
    "stats":{
      "min":null,
      "max":null,
      "avg":null,
      "total":-1,
      "loss":-1,
      "rcv":-1,
      "drop":0
    }
  }
}
```
