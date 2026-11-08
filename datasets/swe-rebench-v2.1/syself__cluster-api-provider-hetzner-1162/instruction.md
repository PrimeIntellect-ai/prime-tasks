Controller should not pick hbmh with one disk, if swraid=true
/kind bug

if the hetzner-bare-metal-machine-template has swraid=true, then the controller should not pick a hbmh which has only one disk.

Up to now the controller picks the hbmh and after several minutes the process fails because installimage fails.

You can see the error message of installimage in the Kubernetes event, but it is not immediately visible.

**What did you expect to happen:**

I expect the controller to ignore machines which have only one WWN in the hbmh, if the hetzner-bare-metal-machine-template has swraid=true.

**Anything else you would like to add:**

We should do the opposite check, too:

If the  hetzner-bare-metal-machine-template has swraid=false, then the controller should not pick a hbmh which has two WWNs.

[hbmh docs](https://github.com/syself/cluster-api-provider-hetzner/blob/ad6342c684236dda19d85fd12a06066dbb46ed76/docs/reference/hetzner-bare-metal-host.md?plain=1#L33)

[hbmmt docs](https://github.com/syself/cluster-api-provider-hetzner/blob/ad6342c684236dda19d85fd12a06066dbb46ed76/docs/reference/hetzner-bare-metal-machine-template.md?plain=1#L47)

Implementation:

There are two lists of WWNs: rootDeviceHints.raid.wwn and rootDeviceHints.wwn.

The controller should only take a machine wher swraid (from the hbmmt) matches the WWN of hbmh.
