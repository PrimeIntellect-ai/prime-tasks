#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/telemetry.jsonl
{"event_id": 1, "raw_log": "[SYSTEM] latency=50ms timestamp=2023-11-01T00:01:00Z status=OK"}
{"event_id": 2, "raw_log": "[SYSTEM] latency=100ms timestamp=2023-11-01T00:02:00Z status=OK", "bad_unicode": "\u004"}
{"event_id": 3, "raw_log": "[SYSTEM] latency=150ms timestamp=2023-11-01T00:03:00Z status=OK"}
{"event_id": 4, "raw_log": "[SYSTEM] latency=-10ms timestamp=2023-11-01T00:04:00Z status=ERR"}
{"event_id": 5, "raw_log": "[SYSTEM] latency=200ms timestamp=2023-11-01T00:05:00Z status=OK", "bad_unicode": "\u12Z"}
{"event_id": 6, "raw_log": "[SYSTEM] latency=6000ms timestamp=2023-11-01T00:06:00Z status=ERR"}
{"event_id": 7, "raw_log": "[SYSTEM] latency=10ms timestamp=2023-11-01T00:07:00Z status=OK"}
EOF

    chmod -R 777 /home/user
