sabnzbd - metrics values
Saw reference to `sabnzbd` metrics being available in latest version.  Working on a Grafana Dashboard for it, but having some issues with 2 metrics:

* `sabnzbd_disk_total_bytes` seems to be reporting size in number of 1K blocks not bytes.  I get `209715200` 1K blocks instead of `214748364800` bytes.

* `sabnzbd_disk_used_bytes` not sure what its reporting as it shows up as a decimal such `207901163.52`. I'm expecting more like `1855259765` bytes (reported by `du -b /downloads`).  Value reported seems closer to free space in 1K blocks `207904768` than used space in bytes.
