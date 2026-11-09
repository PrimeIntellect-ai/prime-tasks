#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sensor_stream.log
[2023-10-01T10:00:00Z] INFO [module_a] sensor_id: SN-1001 | some noise | payload: {"x": 0.0, "y": 0.0}
[2023-10-01T10:05:00Z] DEBUG noise sensor_id: TEST-9999 payload: {"x": 100, "y": 100}
[2023-10-01T10:10:00Z] WARN sensor_id: SN-1001 - payload: {"x": 3.0, "y": null}
[2023-10-01T10:20:00Z] INFO sensor_id: SN-1001 payload: {"x": 6.0, "y": 8.0}
[2023-10-01T10:00:00Z] INFO sensor_id: SN-2002 | payload: {"x": 10.0, "y": 10.0}
[2023-10-01T10:30:00Z] ERROR sensor_id: SN-2002 payload: {"y": 10.0}
[2023-10-01T11:00:00Z] INFO sensor_id: SN-2002 | payload: {"x": 10.0, "y": 10.0}
[2023-10-01T10:00:00Z] INFO sensor_id: SN-3003 payload: {"x": 0.0, "y": 0.0}
[2023-10-01T10:05:00Z] INFO sensor_id: SN-3003 payload: {"x": 5.0}
[2023-10-01T10:10:00Z] INFO sensor_id: SN-3003 payload: {"x": 10.0, "y": 10.0}
[2023-10-01T10:15:00Z] INFO sensor_id: SN-500 | payload: {"x": 0, "y": 0}
EOF

    chmod -R 777 /home/user
