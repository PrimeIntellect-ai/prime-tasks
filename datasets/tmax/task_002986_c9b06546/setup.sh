#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip parallel coreutils
    pip3 install pytest

    mkdir -p /home/user/configs

    cat << 'EOF' > /home/user/configs/serverA.utf8.txt
STATE: ACTIVE
<PAYLOAD>
server_name=app1
timeout=30
</PAYLOAD>
---
STATE: INACTIVE
<PAYLOAD>
server_name=app2
timeout=60
</PAYLOAD>
---
STATE: ACTIVE
<PAYLOAD>
server_name=app3
timeout=120
max_conn=500
</PAYLOAD>
EOF

    cat << 'EOF' > /home/user/configs/serverB_raw.txt
STATE: ACTIVE
<PAYLOAD>
server_name=app1
timeout=30
</PAYLOAD>
---
STATE: ACTIVE
<PAYLOAD>
server_name=app_legacy
db_host=10.0.0.5
</PAYLOAD>
EOF

    iconv -f UTF-8 -t UTF-16LE /home/user/configs/serverB_raw.txt > /home/user/configs/serverB.utf16.txt
    rm /home/user/configs/serverB_raw.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
