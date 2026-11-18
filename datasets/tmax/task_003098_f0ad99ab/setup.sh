#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip coreutils gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cat << 'EOF' > /home/user/sys_updates.wal
1700000000:network:cG9ydD04MAo=
1700000050:database:dXJsPWxvY2FsaG9zdAptYXhfY29ubnM9MTAwCg==
1700000100:network:cG9ydD04MDgwCmhvc3Q9MTI3LjAuMC4xCg==
1700000020:cache:bWVtPTEwMjRNCg==
1700000150:database:dXJsPWxvY2FsaG9zdAptYXhfY29ubnM9NTAwCg==
1700000120:cache:bWVtPTIwNDhNCmV2aWN0PWxydQo=
EOF
    chmod 644 /home/user/sys_updates.wal

    chmod -R 777 /home/user
