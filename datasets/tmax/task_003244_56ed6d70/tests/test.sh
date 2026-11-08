#!/bin/bash
set -e
mkdir -p /logs/verifier

TEST_FILE=$(mktemp /tmp/test_final_state.XXXXXX.py)
trap 'rm -f "$TEST_FILE"' EXIT

cat << 'TEST_EOF' > "$TEST_FILE"
import os
import json
from collections import defaultdict, deque

# Verifier-owned copy of the original input. This is supplied only at
# verification time and cannot be changed by the agent.
ORIGINAL_TRANSFERS_JSONL = r'''{"tx_id": "t01", "source": "NODE_SUSPECT", "target": "NODE_A", "bytes": 500, "status": "COMPLETED"}
{"tx_id": "t02", "source": "NODE_A", "target": "NODE_B", "bytes": 200, "status": "COMPLETED"}
{"tx_id": "t03", "source": "NODE_B", "target": "NODE_VAULT", "bytes": 100, "status": "COMPLETED"}
{"tx_id": "t04", "source": "NODE_SUSPECT", "target": "NODE_C", "bytes": 8000, "status": "FAILED"}
{"tx_id": "t05", "source": "NODE_C", "target": "NODE_VAULT", "bytes": 100, "status": "COMPLETED"}
{"tx_id": "t06", "source": "NODE_X", "target": "NODE_Y", "bytes": 15000, "status": "COMPLETED"}
{"tx_id": "t07", "source": "NODE_X", "target": "NODE_Z", "bytes": 12000, "status": "COMPLETED"}
{"tx_id": "t08", "source": "NODE_Z", "target": "NODE_W", "bytes": 1000, "status": "COMPLETED"}
{"tx_id": "t09", "source": "NODE_SUSPECT", "target": "NODE_D", "bytes": 300, "status": "COMPLETED"}
{"tx_id": "t10", "source": "NODE_D", "target": "NODE_E", "bytes": 300, "status": "COMPLETED"}
{"tx_id": "t11", "source": "NODE_E", "target": "NODE_F", "bytes": 300, "status": "COMPLETED"}
{"tx_id": "t12", "source": "NODE_F", "target": "NODE_VAULT", "bytes": 300, "status": "COMPLETED"}'''


def compute_truth():
    transfers = [
        json.loads(line)
        for line in ORIGINAL_TRANSFERS_JSONL.splitlines()
        if line.strip()
    ]

    completed = [t for t in transfers if t.get("status") == "COMPLETED"]

    bytes_by_source = defaultdict(int)
    for t in completed:
        bytes_by_source[t["source"]] += t["bytes"]

    max_sender = None
    max_bytes = -1
    for source, total_bytes in bytes_by_source.items():
        if total_bytes > max_bytes:
            max_bytes = total_bytes
            max_sender = source

    graph = defaultdict(list)
    for t in completed:
        graph[t["source"]].append(t["target"])

    shortest_path_length = -1
    queue = deque([("NODE_SUSPECT", 0)])
    visited = {"NODE_SUSPECT"}

    while queue:
        current, dist = queue.popleft()
        if current == "NODE_VAULT":
            shortest_path_length = dist
            break

        for neighbor in graph[current]:
            if neighbor not in visited:
                visited.add(neighbor)
                queue.append((neighbor, dist + 1))

    return max_sender, max_bytes, shortest_path_length


def test_audit_report_exists():
    assert os.path.isfile("/home/user/audit_report.txt"), "/home/user/audit_report.txt does not exist."


def test_audit_report_content():
    max_sender, max_bytes, shortest_path_length = compute_truth()
    assert max_sender is not None, "Could not compute truth values."

    expected_lines = [
        f"Highest Transfer Node: {max_sender}",
        f"Highest Transfer Bytes: {max_bytes}",
        f"Shortest Path Length: {shortest_path_length}",
    ]

    with open("/home/user/audit_report.txt", "r") as f:
        content = f.read()

    for expected in expected_lines:
        assert expected in content, f"Expected line '{expected}' not found in /home/user/audit_report.txt."

    expected_content = "\n".join(expected_lines)
    assert content in (expected_content, expected_content + "\n"), \
        "/home/user/audit_report.txt must contain exactly the three required lines in order."
TEST_EOF

if python3 -I -m pytest "$TEST_FILE" -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
