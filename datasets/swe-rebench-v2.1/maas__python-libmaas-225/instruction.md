Cannot move VLAN to the Default Fabric
maas 2.3.5

When a new machine is discovered, my primary 10 gbps interface is assigned to the wrong fabric so when I go to assign a vlan to it, it fails, I assume because the VLAN is part of a different fabric. If I fix the fabric using the GUI and then run my script, it works fine.

So how can I set the fabric in my script?

[set_vlans.txt](https://github.com/maas/python-libmaas/files/3143085/set_vlans.txt)
