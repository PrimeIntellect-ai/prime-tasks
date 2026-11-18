#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/app/tests
    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/logs/producer.log
[2023-10-24 09:59:58] INFO: Sent payload_id: 8f72a-111
[2023-10-24 09:59:59] INFO: Sent payload_id: 8f72a-112
[2023-10-24 10:00:00] INFO: Sent payload_id: 8f72a-113
[2023-10-24 10:00:01] INFO: Sent payload_id: BAD-999-LEAK
[2023-10-24 10:00:02] INFO: Sent payload_id: 8f72a-114
EOF

    cat << 'EOF' > /home/user/logs/syslog
Oct 24 09:59:00 server systemd[1]: Started Consumer Service.
Oct 24 10:00:04 server kernel: [ 1234.567] consumer.py invoked oom-killer: gfp_mask=0x100cca(GFP_HIGHUSER_MOVABLE), order=0, oom_score_adj=0
Oct 24 10:00:05 server kernel: [ 1235.111] Out of memory: Killed process 4123 (python3) total-vm:8388608kB, anon-rss:8192000kB, file-rss:0kB, shmem-rss:0kB, UID:1000 pgtables:16384kB oom_score_adj:0
EOF

    cat << 'EOF' > /home/user/app/consumer.py
import json
import datetime

ERROR_HISTORY = []

def process_payload(json_str):
    global ERROR_HISTORY
    try:
        data = json.loads(json_str)
        # Expecting format YYYY-MM-DD
        dt = datetime.datetime.strptime(data['date'], '%Y-%m-%d')
        return dt.isoformat()
    except ValueError as e:
        # BUG: memory leak if this happens frequently or with large payloads
        # The edge case payload uses YYYY/MM/DD format
        ERROR_HISTORY.append({"error": str(e), "raw_payload": json_str * 10000}) # Exaggerated leak
        return None
EOF

    cat << 'EOF' > /home/user/app/tests/test_consumer.py
import pytest
from consumer import process_payload, ERROR_HISTORY

def test_process_payload_valid():
    assert process_payload('{"date": "2023-10-24"}') == '2023-10-24T00:00:00'

def test_process_payload_invalid_records_error():
    global ERROR_HISTORY
    initial_len = len(ERROR_HISTORY)
    process_payload('{"date": "2023/10/24"}')
    # This test ensures the old broken behavior! The agent must update this test
    # after fixing the code to handle "YYYY/MM/DD" gracefully without erroring.
    assert len(ERROR_HISTORY) == initial_len + 1
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
