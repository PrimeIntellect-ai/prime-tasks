Add support for `/proc/net/wireless` parsing
To collect wireless RSSI values using procfs. We can also add this support to node_exporter once we implement this.

Example:
```
$ cat /proc/net/wireless

Inter-| sta-|   Quality        |   Discarded packets               | Missed | WE
 face | tus | link level noise |  nwid  crypt   frag  retry   misc | beacon | 22

wlo1: 0000   70.  -31.  -256        0      0      0      0     25        0
```

/assign

### Additional contract requirements

Provide `FS.Wireless() ([]*Wireless, error)` to read the proc filesystem associated with an `FS` and return the wireless data for each interface in `/proc/net/wireless`. Each returned `Wireless` value must expose the interface name in `Name` and its signed signal-level value in `QualityLevel`, so callers can collect RSSI values.
