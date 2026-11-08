Using `wwctl` to set tags causes profile set tags to be overridden by empty values.
### Version of Warewulf

`git` `development` branch

### Expected behavior

`wwctl node set --tagadd="testing=MYPLACEHOLDER" cpu-vm-1` adds the given tag to the node config.

### Actual behavior

Node config before adding tag:

```
  cpu-vm-1:
    cluster name: bruno
    ipmi:
      write: "false"
    profiles:
    - role-compute-dev
    - site-tags-bruno
    - site-network-bruno
    network devices:
      clusternet:
        type: ethernet
        onboot: "true"
        device: enp1s0
        hwaddr: 52:54:00:63:ba:20
        ipaddr: 100.64.0.241
        primary: "false"
        tags:
          defroute: "true"
          firewalld_zone: public
          mtu: ""
      infiniband:
        type: infiniband
        onboot: "true"
        device: ib0
        hwaddr: ca:fe:64:24:00:00
        ipaddr: 100.64.18.129
        primary: "false"
        tags:
          firewalld_zone: trusted
          ibclientid: ff:00:00:00:00:00:02:00:00:02:c9:00:ca:fe:64:40:00:24:00:00
          ibhwaddr: 00:00:00:e9:fe:80:00:00:00:00:00:00:ca:fe:64:40:00:24:00:00
          ibportguid: ca:fe:64:40:00:24:00:00
    tags:
      role: compute
```

Node config after using `wwctl` to add tag:

```
  cpu-vm-1:
    cluster name: bruno
    ipmi:
      write: "false"
    profiles:
    - role-compute-dev
    - site-tags-bruno
    - site-network-bruno
    network devices:
      clusternet:
        type: ethernet
        onboot: "true"
        device: enp1s0
        hwaddr: 52:54:00:63:ba:20
        ipaddr: 100.64.0.241
        primary: "false"
        tags:
          defroute: "true"
          firewalld_zone: public
          mtu: ""
      default: {}
      infiniband:
        type: infiniband
        onboot: "true"
        device: ib0
        hwaddr: ca:fe:64:24:00:00
        ipaddr: 100.64.18.129
        primary: "false"
        tags:
          firewalld_zone: trusted
          ibclientid: ff:00:00:00:00:00:02:00:00:02:c9:00:ca:fe:64:40:00:24:00:00
          ibhwaddr: 00:00:00:e9:fe:80:00:00:00:00:00:00:ca:fe:64:40:00:24:00:00
          ibportguid: ca:fe:64:40:00:24:00:00
    tags:
      chrony_allow_subnets: ""
      chrony_server1: ""
      chrony_server2: ""
      chrony_server3: ""
      lustre_exa1: ""
      lustre_lnet_devices: ""
      nfs_admin: ""
      nfs_archives: ""
      nfs_ess: ""
      nfs_groupscratch: ""
      nfs_home: ""
      nfs_instruments: ""
      nfs_mydata: ""
      nfs_slurm: ""
      nfs_software: ""
      nfs_websites: ""
      role: compute
      testing: MYPLACEHOLDER
      timezone: ""
```

Empty tags are all set in a profile which is included in the nodes list of profiles. Since node specific tags override profile tags, this effectively breaks all tags that were set in profiles.

### Steps to reproduce this behavior

Add tag with `wwctl`

### What OS/distro are you running

Rocky 8.7

### How did you install Warewulf

Built from source, `development` branch.

@mslacken note that it also adds an empty default network device, that thing just refuses to die.
