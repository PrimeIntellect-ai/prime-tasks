Ceph CSI update to 3.14.2
The Ceph CSI driver's LUKS helper had a non-standard implementation of calling `cryptsetup`, causing issues in Talos Linux. See https://github.com/ceph/ceph-csi/issues/5306 and https://github.com/siderolabs/talos/issues/10473 for more details.

This has been [fixed](https://github.com/ceph/ceph-csi/pull/5307) and [backported](https://github.com/ceph/ceph-csi/pull/5407) to Ceph CSI 3.14.2.

Now, for me and other users experiencing issues due to this, it would be [great](https://github.com/siderolabs/talos/issues/10473#issuecomment-2868773065) if Rook could release a new (patch) version with the 3.14.2 release of Ceph CSI included.
