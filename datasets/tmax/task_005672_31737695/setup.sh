#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/waits_for.csv
waiter_id,holder_id,wait_start_time
101,102,1620000100
102,103,1620000110
103,101,1620000120
201,202,1620000050
202,203,1620000060
203,201,1620000130
301,302,1620000080
302,303,1620000085
303,301,1620000090
401,402,1620000200
402,403,1620000210
501,502,1620000090
502,503,1620000090
503,501,1620000090
EOF

    chmod -R 777 /home/user
