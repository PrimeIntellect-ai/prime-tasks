#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip xxd gawk coreutils sed grep
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/known_commands.txt
ls -la /var/log
cat /etc/passwd
whoami
EOF

    cat << 'EOF' > /home/user/audit.log.enc
27386b66272a6b643d2a396427242c
282a3f6b642e3f28643b2a38383c2f
3c23242a2622
EOF

    chmod -R 777 /home/user
