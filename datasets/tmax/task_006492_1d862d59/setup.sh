#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gawk
pip3 install pytest

mkdir -p /home/user/evidence

echo -n "S3cr3t_F0r3ns1cs_M4st3rK3y" > /home/user/evidence/.secret_key

cat << 'EOF' > /home/user/evidence/forge_token.sh
#!/bin/bash
# Usage: ./forge_token.sh <username> <timestamp>
USER=$1
TS=$2
SECRET=$(cat $(dirname $0)/.secret_key)
# Token is SHA256 of USER:TS:SECRET
echo -n "${USER}:${TS}:${SECRET}" | sha256sum | awk '{print $1}'
EOF
chmod +x /home/user/evidence/forge_token.sh

cat << 'EOF' > /home/user/evidence/auth_service_mock.sh
#!/bin/bash
if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <username> <timestamp> <token>"
    exit 1
fi
EXPECTED=$(echo -n "$1:$2:S3cr3t_F0r3ns1cs_M4st3rK3y" | sha256sum | awk '{print $1}')
if [ "$EXPECTED" == "$3" ]; then
    echo "AUTH SUCCESS"
    exit 0
else
    echo "AUTH FAILED"
    exit 1
fi
EOF
chmod +x /home/user/evidence/auth_service_mock.sh

cat << 'EOF' > /home/user/evidence/privesc_scan.log
-rwsr-xr-x 1 root root 64424 Jan 10  2023 /usr/bin/passwd
-rwsr-xr-x 1 root root 155008 Feb 20  2023 /usr/bin/sudo
-rwsr-xr-x 1 root root 42000 Mar 15  2023 /usr/bin/su
-rwsr-xr-x 1 root root 32840 Apr 05  2023 /usr/bin/newgrp
-rwsr-xr-x 1 root root 85040 May 11  2023 /usr/bin/chfn
-rwsr-xr-x 1 root root 54200 Jun 18  2023 /usr/bin/chsh
-rwsrwxr-x 1 root root 10240 Nov 01 12:34 /opt/internal/sys_backup_mgr
-rwsr-xr-x 1 root root 34000 Dec 01  2022 /usr/bin/mount
-rwsr-xr-x 1 root root 28000 Dec 01  2022 /usr/bin/umount
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
