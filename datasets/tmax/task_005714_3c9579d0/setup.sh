#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c "
import os

events = [
    (1700000005, 'NET', 'fw_update'),
    (1700000005, 'NET', 'fw_update'),
    (1700000010, 'SEC', 'key_rotate'),
    (1700000045, 'NET', 'fw_patch'),
    (1700000125, 'DB', 'schema_v2'),
    (1700000150, 'DB', 'schema_v2_retry'),
    (1700000155, 'SEC', 'acl_update'),
    (1700000200, 'DB', 'index_build'),
]

with open('/home/user/config_events.csv', 'w') as f:
    for ts, cat, desc in events:
        f.write(f'{ts},{cat},{desc}\n')
"

    chown 1000:1000 /home/user/config_events.csv
    chmod -R 777 /home/user
