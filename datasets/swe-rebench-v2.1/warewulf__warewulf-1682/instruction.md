wwctl overlay list shows both site and distribution overlay as site overlay
### Steps to reproduce

- Create a site overlay that shadows a distribution overlay
- `wwctl overlay list`

### Error message

The overlay is shown twice, but both are marked as a site overlay.

### Information on your system

```
[root@wwctl2 demo]# wwctl version
wwctl version:	 4.6.0rc1-1
rpc version: apiPrefix:"rc1"  apiVersion:"1"  warewulfVersion:"4.6.0rc1-1"
[root@wwctl2 demo]# cat /etc/os-release
NAME="Rocky Linux"
VERSION="9.4 (Blue Onyx)"
ID="rocky"
ID_LIKE="rhel centos fedora"
VERSION_ID="9.4"
PLATFORM_ID="platform:el9"
PRETTY_NAME="Rocky Linux 9.4 (Blue Onyx)"
ANSI_COLOR="0;32"
LOGO="fedora-logo-icon"
CPE_NAME="cpe:/o:rocky:rocky:9::baseos"
HOME_URL="https://rockylinux.org/"
BUG_REPORT_URL="https://bugs.rockylinux.org/"
SUPPORT_END="2032-05-31"
ROCKY_SUPPORT_PRODUCT="Rocky-Linux-9"
ROCKY_SUPPORT_PRODUCT_VERSION="9.4"
REDHAT_SUPPORT_PRODUCT="Rocky Linux"
REDHAT_SUPPORT_PRODUCT_VERSION="9.4"
```

### General information

- [x] I have run `wwctl version` and reported the contents of `/etc/os-release`
- [x] I have searched the issues of this repo and believe this is not a duplicate
- [x] I have captured and reported relevant error messages and logs

### Additional contract requirements

- A public function `FindOverlays()` in package `internal/pkg/overlay` that returns the combined list of overlay names as a `[]string`. When the same overlay name exists as both a distribution overlay and a site overlay, it must appear in the returned list only once.
- Overlay names that begin with a dot, and entries that are not directories, are not included in the returned list.
