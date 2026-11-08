#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user/vm_logs
    mkdir -p /home/user/mailspool
    mkdir -p /home/user/.config/systemd/user

    cat << 'EOF' > /home/user/fstab.conf
# /etc/fstab: static file system information.
/dev/vda1 / ext4 defaults 1 1
/dev/vdb1 /home/user/vm_logs ext4 ro,nosuid,nodev,nofail 0 2
/dev/vdc1 /mnt/data xfs defaults 0 0
EOF

    cat << 'EOF' > /home/user/qemu.opts
-m 2048 -enable-kvm -drive file=ubuntu.qcow2,format=qcow2 -vnc 127.0.0.1:7 -netdev user,id=n1 -device virtio-net,netdev=n1
EOF

    cat << 'EOF' > /home/user/vm_logs/network.log
[10:00:01] INFO: Link up
[10:05:22] ERROR: CONNECTIVITY_LOST
[10:05:25] INFO: Retrying...
[10:05:30] ERROR: CONNECTIVITY_LOST
[10:06:00] INFO: Link up
[10:15:10] ERROR: CONNECTIVITY_LOST
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
