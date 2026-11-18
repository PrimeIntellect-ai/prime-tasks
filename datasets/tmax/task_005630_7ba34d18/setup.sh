#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_logs.csv
timestamp,user_id,log_message
1620000005,user_2,"SYSTEM_STARTUP_SEQUENCE_INITIATED"
1620000001,user_1,"This is a normal log"
1620000010,user_3,"Log with
an embedded newline"
1620000002,user_1,""
1620000020,user_4,"SYSTEM_STARTUP_SEQUENCE_INITIATED with
extra
lines"
EOF

    chmod -R 777 /home/user
