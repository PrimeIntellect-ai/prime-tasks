#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron qemu-system-x86
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/legacy_users.txt
alice:wheel:/bin/bash
bob:developers:/bin/bash
charlie:interns:/bin/sh
david:wheel:/bin/zsh
eve:contractors:/bin/bash
EOF

    chmod -R 777 /home/user
