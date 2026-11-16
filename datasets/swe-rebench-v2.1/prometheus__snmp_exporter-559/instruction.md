EnumAsInfo panic

### Host operating system: output of `uname -a`

### snmp_exporter version: output of `snmp_exporter -version`

version=0.16.1

### What device/snmpwalk OID are you using?

snmp.yml:
```
  - name: ciscoEnvMonSupplyStatusIndex
    oid: 1.3.6.1.4.1.9.9.13.1.5.1.1
    type: gauge
    help: Unique index for the power supply being instrumented - 1.3.6.1.4.1.9.9.13.1.5.1.1
    indexes:
    - labelname: ciscoEnvMonSupplyStatusIndex
      type: gauge
```

### If this is a new device, please link to the MIB(s).

### What did you do that produced an error?

Set an `EnumAsInfo`

### What did you expect to see?

### What did you see instead?

```
snmp_exporter[1138]: panic: Unknown index type EnumAsInfo
snmp_exporter[1138]: goroutine 1918149 [running]:
snmp_exporter[1138]: main.indexOidsAsString(0xc0008ee4e8, 0x1, 0x3, 0xc0011c54f0, 0xa, 0x0, 0xab9200, 0xc000192a40, 0x0, 0x0, ...)
snmp_exporter[1138]: #011/app/collector.go:662 +0x1870
snmp_exporter[1138]: main.indexesToLabels(0xc0008ee4e8, 0x1, 0x3, 0xc00131dc00, 0xc0006bbaa0, 0x4)
snmp_exporter[1138]: #011/app/collector.go:673 +0x169
snmp_exporter[1138]: main.pduToSamples(0xc0008ee4e8, 0x1, 0x3, 0xc0006bbad0, 0xc00131dc00, 0xc0006bbaa0, 0xaaf060, 0xc000721e60, 0xc000d36a50, 0x1, ...)
snmp_exporter[1138]: #011/app/collector.go:326 +0x77
snmp_exporter[1138]: main.collector.Collect(0xc000d6a025, 0x11, 0xc0001752c0, 0xaaf060, 0xc000721e60, 0xc001252e40)
snmp_exporter[1138]: #011/app/collector.go:244 +0x914
snmp_exporter[1138]: github.com/prometheus/client_golang/prometheus.(*Registry).Gather.func1()
snmp_exporter[1138]: #011/app/vendor/github.com/prometheus/client_golang/prometheus/registry.go:443 +0x19d
snmp_exporter[1138]: created by github.com/prometheus/client_golang/prometheus.(*Registry).Gather
snmp_exporter[1138]: #011/app/vendor/github.com/prometheus/client_golang/prometheus/registry.go:454 +0x57d
```

It turns out I made an incorrect override for `ciscoEnvMonSupplyStatusIndex` as an `EnumAsInfo`. So this is possibly a generator safety check that is needed to avoid allowing enum types for OIDs that don't have `enum_values`.

### Additional contract requirements

- When an `EnumAsInfo` index has a configured `enum_values` entry for its raw OID code, its label is the mapped text.
- An `EnumAsInfo` index represents one OID component, so subsequent index definitions use the remaining components.
- An `EnumAsInfo` index without a mapping for its raw code must not cause an uncaught panic during collection; it may be handled safely or rejected before collection.
