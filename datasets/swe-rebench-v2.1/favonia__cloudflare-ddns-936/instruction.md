Ban IPv4-mapped IPv6 addresses in AAAA records
Using IPv4-mapped IPv6 addresses in AAAA records has caused lots of issues and should be seriously warned. The code should be reviewed along with implementing #889. Given that the goal is to detect _public_ IPs, maybe the updater should err out!

### Additional contract requirements

- When IPv6 normalization encounters an IPv4-mapped IPv6 address, reject it. Emit an error notice stating `Detected IP address <address> is an IPv4-mapped IPv6 address`, followed by a hint identified by `HintIP4MappedIP6Address` stating: `An IPv4-mapped IPv6 address is an IPv4 address in disguise. It cannot be used for routing IPv6 traffic. If you need to use it for DNS, please open an issue at <issue reporting URL>`. Use the address and issue reporting URL in their respective placeholders.
- When a plain IPv4 address is supplied for IPv6 normalization, reject it and emit an error notice stating `Detected IP address <address> is not a valid IPv6 address`, using the supplied address.
