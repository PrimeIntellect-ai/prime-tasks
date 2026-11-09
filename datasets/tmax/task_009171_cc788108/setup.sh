#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron
    pip3 install pytest

    mkdir -p /home/user/incoming
    mkdir -p /home/user/processed
    mkdir -p /home/user/pipeline

    cat << 'EOF' > /home/user/incoming/batch1.csv
id,feedback
1,The battery life is terrible\u002e
2,Love the screen\u0021 Very bright.
EOF

    cat << 'EOF' > /home/user/incoming/batch2.csv
id,feedback
3,Terrible\u0021 Will return.
4,"bright screen, love it"
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/incoming /home/user/processed /home/user/pipeline
    chmod -R 777 /home/user
