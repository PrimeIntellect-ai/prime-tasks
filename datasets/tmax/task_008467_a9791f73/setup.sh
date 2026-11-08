#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip rustc cargo qemu-system-x86
pip3 install pytest

mkdir -p /home/user
touch /home/user/bzImage

cat << 'EOF' > /home/user/cloud_fstab
10.0.0.5:/var/nfs /mnt/nfs_share nfs defaults 0 0
//10.0.0.6/smb /mnt/smb_share cifs credentials=/etc/smbcredentials 0 0
/dev/sda1 / ext4 defaults 1 1
10.0.1.5:/var/nfs2 /mnt/nfs2 nfs ro 0 0
//10.0.1.6/smb2 /mnt/smb2 cifs defaults 0 0
/dev/sdb1 /data xfs defaults 0 0
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
