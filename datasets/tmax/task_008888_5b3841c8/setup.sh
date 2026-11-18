#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/storage/alice_data
    mkdir -p /home/user/storage/bob_data
    mkdir -p /home/user/storage/charlie_data

    cat << 'EOF' > /home/user/custom_fstab
/dev/loop1 /home/user/storage/alice_data ext4 rw,uid=1001,quota=50000 0 0
/dev/loop2 /home/user/storage/bob_data ext4 rw,uid=1002,quota=20000 0 0
/dev/loop3 /home/user/storage/charlie_data ext4 rw,uid=1003,quota=10000 0 0
EOF

    cat << 'EOF' > /home/user/mock_passwd
alice:x:1001:1001::/home/alice:/bin/bash
bob:x:1002:1002::/home/bob:/bin/bash
charlie:x:1003:1003::/home/charlie:/bin/bash
EOF

    head -c 30000 /dev/zero > /home/user/storage/alice_data/data.bin
    head -c 25000 /dev/zero > /home/user/storage/bob_data/data.bin
    head -c 15000 /dev/zero > /home/user/storage/charlie_data/data.bin

    chmod -R 777 /home/user
