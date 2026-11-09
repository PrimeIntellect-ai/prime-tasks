#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_configs.log
[2023-10-01 08:00:00] INFO - ETL processing config state. target_server=srv-alpha snapshot_hash=hash-a1 retry_count=0
[2023-10-01 09:15:00] INFO - ETL processing config state. target_server=srv-beta snapshot_hash=hash-b1 retry_count=0
[2023-10-01 14:00:00] INFO - ETL processing config state. target_server=srv-alpha snapshot_hash=hash-a2 retry_count=1
[2023-10-03 10:00:00] INFO - ETL processing config state. target_server=srv-alpha snapshot_hash=hash-a3 retry_count=0
[2023-10-05 11:22:33] INFO - ETL processing config state. target_server=srv-beta snapshot_hash=hash-b2 retry_count=0
[2023-10-05 15:00:00] INFO - ETL processing config state. target_server=srv-alpha snapshot_hash=hash-a4 retry_count=0
[2023-10-05 15:30:00] INFO - ETL processing config state. target_server=srv-alpha snapshot_hash=hash-a5 retry_count=1
EOF

    chmod -R 777 /home/user
