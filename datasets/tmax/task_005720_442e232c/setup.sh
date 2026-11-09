#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/requests.txt
alice,2201,/home/user/jails/alice/share
bob,2202,/home/user/jails/bob/share
invalid_user,2203
charlie,2204,/home/user/jails/charlie/share

badformat_no_port
eve,2205,/home/user/jails/eve/share
EOF

    chmod -R 777 /home/user
