#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/mock_fstab
# /etc/fstab: static file system information.
UUID=1234-5678  /               btrfs   defaults        0       0
/dev/sda1       /boot/efi       vfat    umask=0077      0       1
/dev/sdb1       /mnt/storage    ext4    defaults,noatime 0       2
10.0.0.5:/nfs   /mnt/nfs_share  nfs     defaults        0       0
/dev/sdc1       /data/db_disk   ext4    ro,nosuid       0       2
EOF
    chmod 644 /home/user/mock_fstab

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
