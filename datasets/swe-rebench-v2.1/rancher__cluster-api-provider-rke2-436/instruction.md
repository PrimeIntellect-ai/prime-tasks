NTP API broken for Leap/SLEMicro
**What happened:**

We provide an [API for NTP configuration](https://github.com/rancher/cluster-api-provider-rke2/blob/main/bootstrap/api/v1beta1/rke2config_types.go#L88) which influences the firstboot configuration to configure/enable  a NTP client.

In the `format: ignition` case we can see the [relevant templating](https://github.com/rancher/cluster-api-provider-rke2/blob/main/bootstrap/internal/ignition/butane/butane.go#L65) e.g:

```
./butane/butane.go:    {{- if .NTPServers }}
./butane/butane.go:    - name: ntpd.service
./butane/butane.go:    {{- if .NTPServers }}
```

However our primary target for ignition support is Leap/SLEMicro, which doesn't include ntpd, it uses chrony instead, so we see an ignition error like:

`Failed to enable unit, unit ntpd.service does not exist.`

**What did you expect to happen:**
We should configure/enable chrony instead as described in [the SLEMicro docs](https://documentation.suse.com/sle-micro/6.0/html/Micro-ntp-time-synchronization/index.html#ntp-configure-configuration-file)

**How to reproduce it:**
Deploy with NTP servers defined/enabled - observe error and that the OS client is not configured

**Environment:**
- rke provider version: 0.6.1
- OS : Leap/SLEMicro 5.5/6.0
