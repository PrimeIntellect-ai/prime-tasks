#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/server1.log
100 10.0.0.1 START
100 10.0.0.2 START
101 10.0.0.1 REPEAT
102 10.0.0.3 START
105 10.0.0.1 END
EOF

    cat << 'EOF' > /home/user/server2.log
99 10.0.0.1 PRE
101 10.0.0.2 ACTION
102 10.0.0.1 ACTION
102 10.0.0.2 POST
101 10.0.0.1 ACTION
102 10.0.0.2 END
EOF

    chmod -R 777 /home/user
