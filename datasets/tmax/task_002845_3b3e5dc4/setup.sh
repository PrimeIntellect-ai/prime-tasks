#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/server_alpha.log
[1700000000] host=alpha reqs=5
[1700000001] host=alpha reqs=2
[1700000004] host=alpha reqs=8
[1700000005] host=alpha reqs=3
[1700000010] host=alpha reqs=1
[1700000012] host=alpha reqs=6
[1700000015] host=alpha reqs=4
EOF

    cat << 'EOF' > /home/user/server_beta.log
[1700000002] host=beta reqs=4
[1700000004] host=beta reqs=8
[1700000006] host=beta reqs=2
[1700000009] host=beta reqs=5
[1700000010] host=beta reqs=3
[1700000011] host=beta reqs=7
[1700000015] host=beta reqs=4
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
