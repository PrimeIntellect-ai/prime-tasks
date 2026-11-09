#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip netcat-openbsd
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/provisioning/configs
    mkdir -p /home/user/provisioning/logs

    touch /home/user/provisioning/logs/debug-1.old
    touch /home/user/provisioning/logs/debug-2.old
    touch /home/user/provisioning/logs/trace.old

    touch /home/user/provisioning/logs/keep1.log
    touch /home/user/provisioning/logs/keep2.log

    cat << 'EOF' > /home/user/provisioning/configs/prod.conf
google.com 443
cloudflare-dns.com 53
this-domain-does-not-exist.local 8080
EOF

    cat << 'EOF' > /home/user/provisioning/configs/staging.conf
localhost 80
EOF

    chmod -R 777 /home/user
