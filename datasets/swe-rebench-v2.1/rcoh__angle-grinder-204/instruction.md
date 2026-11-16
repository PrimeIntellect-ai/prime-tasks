Crash while parsing netfilter using regex
While trying to write a regex that will parse netfilter logs, I managed to crash agrind (again, sorry!)

Command line:

```
cat netfilter.logs | agrind '* | parse regex "^(?P<timestamp>\S+) (?P<hostname>\S+) kernel: \[[0-9\.]*\] (?P<tag>.*?) IN=(?P<in>\S*) OUT=(?P<out>\S*) (?P<x1>MAC=(?P<mac>\S+) )?SRC=(?P<src>\S+) DST=(?P<dest>\S+) LEN=(?P<len>\S+) TOS=(?P<tos>\S+) PREC=(?P<prec>\S+) TTL=(?P<ttl>[0-9]+) ID=(?P<id>\S+) (?P<x5>(?P<dont_fragment>DF) )?PROTO=(?P<protocol>\S+) (?P<x4>TYPE=(?P<icmp_type>[0-9]+) CODE=(?P<icmp_code>[0-9]+) \[.*?\])?(?P<x2>SPT=(?P<sport>[0-9]+) DPT=(?P<dport>[0-9]+) (?P<x3>WINDOW=(?P<window>\S+) RES=(?P<res>\S+) (?P<flags>.*) URGP=(?P<ugrp>\S+))?)?(?P<x6>LEN=(?P<length>[0-9]+))?$"'
```

I'm _reasonably_ confident that the regex is correct - it's definitely the most complex I've ever done, but I debugged it with https://regex101.com/ using the rust setting, and all my test lines passed there for the above regex.

`netfilter.logs` contents:

```
2023-05-02T11:12:50.823305+00:00 fw.example.com kernel: [576812.045483] Firewall: DROPPED IN=bond1 OUT=bond1 MAC=9e:ee:03:11:12:05:00:1f:6d:b5:18:00:08:00 SRC=192.0.2.100 DST=192.0.2.200 LEN=40 TOS=0x00 PREC=0x00 TTL=242 ID=46326 PROTO=TCP SPT=123 DPT=456 WINDOW=1024 RES=0x00 SYN URGP=0
2023-05-02T11:00:01.786039+00:00 fw1.example.com kernel: [578791.811376] Firewall IN=ens5 OUT=ens6 MAC=2a:e8:c0:3e:4b:17:ae:f6:8c:55:e9:a3:08:00 SRC=192.0.2.111 DST=192.0.2.222 LEN=226 TOS=0x00 PREC=0xC0 TTL=63 ID=24087 PROTO=ICMP TYPE=3 CODE=3 [SRC=10.10.10.10 DST=10.20.30.40 LEN=198 TOS=0x00 PREC=0x80 TTL=122 ID=3067 PROTO=UDP SPT=53 DPT=36506 LEN=178 ]
2023-05-02T11:00:02.136051+00:00 fwall kernel: [2839042.118073] [FIREWALL][OUTPUT] IN= OUT=ens5 SRC=192.0.2.11 DST=192.0.2.22 LEN=60 TOS=0x00 PREC=0x00 TTL=64 ID=11993 DF PROTO=TCP SPT=60488 DPT=443 WINDOW=62727 RES=0x00 SYN URGP=0
2023-05-02T11:00:07.372179+00:00 foo.example.net kernel: [2765257.090978] [FIREWALL][OUTPUT] IN= OUT=ens3 SRC=192.0.2.123 DST=192.0.2.321 LEN=339 TOS=0x00 PREC=0xC0 TTL=64 ID=21371 DF PROTO=UDP SPT=68 DPT=67 LEN=319
```

FWIW, I'm hoping to contribute this back as an alias. Here's my WIP branch: https://github.com/fukawi2/angle-grinder/tree/phs/add-netfilter

[report-9f23892a-d887-4a5e-bedc-cdf9b7c4ea85.txt](https://github.com/rcoh/angle-grinder/files/11531230/report-9f23892a-d887-4a5e-bedc-cdf9b7c4ea85.txt)

### Additional contract requirements

- When an optional named capture does not match, represent its value as `None` in the output.
