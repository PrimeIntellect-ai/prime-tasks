Support RFC 3430
While it's not common, some devices do support [RFC 3430](https://tools.ietf.org/html/rfc3430), SNMP over TCP. The upstream gosnmp library supports this, so it should be an easy thing to add.

### Additional contract requirements

A scrape can select TCP by using a target in the form `tcp://host[:port]`. The exporter must send SNMP requests to that target over TCP.
