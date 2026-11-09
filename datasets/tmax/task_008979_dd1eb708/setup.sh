#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl netcat-openbsd cargo
    pip3 install pytest

    mkdir -p /home/user/app_users/alice
    mkdir -p /home/user/app_users/bob
    mkdir -p /home/user/config
    mkdir -p /home/user/.config/systemd/user/

    cat << 'EOF' > /home/user/config/groups.json
{
  "alice": 1024,
  "bob": 5000
}
EOF

    head -c 1500 /dev/zero > /home/user/app_users/alice/file1.dat
    head -c 2000 /dev/zero > /home/user/app_users/bob/file1.dat

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
