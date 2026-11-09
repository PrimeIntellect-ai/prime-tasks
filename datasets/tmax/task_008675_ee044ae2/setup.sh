#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils sed
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw

    cat << 'EOF' > /home/user/raw/app.log
[2023-10-15 10:05:00] error: Connection reset
[2023-10-15 10:07:15] fatal: Out of memory
[2023-10-15 09:15:00] info: Startup complete
EOF

    cat << 'EOF' > /home/user/raw/sec.log
10/15/2023 10:04:30 WARN: Failed auth
10/15/2023 10:06:00 crit: Intrusion detected
EOF

    chown -R user:user /home/user/raw
    chmod -R 777 /home/user
