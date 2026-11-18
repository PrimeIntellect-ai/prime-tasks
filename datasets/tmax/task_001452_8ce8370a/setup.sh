#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_logs.csv
server_id,report_text
srv-01,"The CPU load is at 45% currently. Mem is 12GB."
srv-02,"Warning: 90% CPU detected. Memory usage: 8GB."
srv-01,"Normal operations, CPU 31%, utilizing 4GB memory."
srv-03,"Critical! CPU is 99% and RAM is 32GB."
srv-02,"CPU 80%. RAM 8GB."
EOF

    chmod -R 777 /home/user
