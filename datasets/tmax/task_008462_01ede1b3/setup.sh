#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sensor_data.wal
---BEGIN_ENTRY---
{"sensor_id": "S1", "timestamp": "2023-10-01T10:00:00Z", "reading": 42.5}
---END_ENTRY---
---BEGIN_ENTRY---
{"sensor_id": "S2", "timestamp": "2023-10-01T10:00:01Z", "reading": 43.1}
---BEGIN_ENTRY---
{"sensor_id": "S3", "timestamp": "2023-10-01T10:00:02Z", "reading": 41.9}
---END_ENTRY---
---BEGIN_ENTRY---
{"sensor_id": "S1", "timestamp": "2023-10-01T10:00:03Z", "reading": 42.0, "extra": "data"}
---END_ENTRY---
---BEGIN_ENTRY---
{"sensor_id": "S4", "timestamp": "2023-10-01T10:00:04Z", "reading": 
EOF

    chmod -R 777 /home/user
