#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c "
import csv
data = [
    ['server_id', 'max_connections', 'timeout', 'retry_policy'],
    ['srv-001', '100', '30', 'fast\nfallback'],
    ['srv-002', '100', '30', 'fast\nfallback'],
    ['srv-003', '100', '30', 'fast\nfallback'],
    ['srv-004', '100', '300', 'fast\nfallback'],
    ['srv-005', '100', '30', 'fast\nfallback'],
]
with open('/home/user/config_dumps.csv', mode='w', encoding='utf-16le', newline='') as f:
    writer = csv.writer(f)
    writer.writerows(data)
"

    chmod -R 777 /home/user
