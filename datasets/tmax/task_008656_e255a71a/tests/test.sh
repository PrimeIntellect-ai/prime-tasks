#!/bin/bash
set -u
mkdir -p /logs/verifier

echo "0" > /logs/verifier/reward.txt

BACKUP_DIR=$(mktemp -d /tmp/audit-verifier.XXXXXX)
ORIGINAL_REPORT="$BACKUP_DIR/original_audit_report.json"
HAVE_BACKUP=0
HAVE_REPORT=0

restore_files() {
    if [ "$HAVE_BACKUP" -eq 1 ]; then
        cp -p "$BACKUP_DIR/employees.csv" /home/user/employees.csv
        cp -p "$BACKUP_DIR/access_logs.jsonl" /home/user/access_logs.jsonl
    fi
    if [ "$HAVE_REPORT" -eq 1 ]; then
        cp -p "$ORIGINAL_REPORT" /home/user/audit_report.json
    fi
    rm -rf "$BACKUP_DIR" /tmp/verifier-gocache
}
trap restore_files EXIT

if [ ! -f /home/user/employees.csv ] || [ ! -f /home/user/access_logs.jsonl ]; then
    exit 0
fi
if [ ! -s /home/user/workspace/go.mod ]; then
    exit 0
fi
if ! find /home/user/workspace -type f -name '*.go' -print -quit | grep -q .; then
    exit 0
fi

cp -p /home/user/employees.csv "$BACKUP_DIR/employees.csv"
cp -p /home/user/access_logs.jsonl "$BACKUP_DIR/access_logs.jsonl"
HAVE_BACKUP=1
mkdir -p /tmp/verifier-gocache
chmod 777 /tmp/verifier-gocache

cat << 'TEST_EOF' > "$BACKUP_DIR/test_final_state.py"
import os
import json
import pytest
from collections import defaultdict, deque

def load_graph():
    logs_path = "/home/user/access_logs.jsonl"
    assert os.path.exists(logs_path), f"File {logs_path} is missing."

    graph = defaultdict(list)
    out_degree = defaultdict(int)

    with open(logs_path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            data = json.loads(line)
            grantor = data.get("grantor_id")
            grantee = data.get("grantee_id") or data.get("resource_id")
            if grantor and grantee:
                graph[grantor].append(grantee)
                out_degree[grantor] += 1

    return graph, out_degree

def compute_shortest_path_length(graph, start, end):
    queue = deque([(start, 1)])
    visited = {start}

    while queue:
        node, dist = queue.popleft()
        if node == end:
            return dist
        for neighbor in graph[node]:
            if neighbor not in visited:
                visited.add(neighbor)
                queue.append((neighbor, dist + 1))
    return float('inf')

def test_audit_report_exists_and_format():
    report_path = "/home/user/audit_report.json"
    assert os.path.exists(report_path), f"Output file {report_path} does not exist."

    with open(report_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {report_path} is not valid JSON.")

    assert isinstance(data, dict), "audit_report.json must contain a JSON object."
    assert set(data.keys()) == {"shortest_path", "top_grantors"}, \
        "audit_report.json must have exactly the keys 'shortest_path' and 'top_grantors'."
    assert "shortest_path" in data, "Key 'shortest_path' is missing from audit_report.json."
    assert "top_grantors" in data, "Key 'top_grantors' is missing from audit_report.json."

    assert isinstance(data["shortest_path"], list), "'shortest_path' must be a list."
    assert isinstance(data["top_grantors"], list), "'top_grantors' must be a list."

def test_shortest_path_validity():
    report_path = "/home/user/audit_report.json"
    if not os.path.exists(report_path):
        pytest.fail(f"File {report_path} is missing.")

    with open(report_path, 'r') as f:
        data = json.load(f)

    path = data.get("shortest_path", [])
    assert len(path) > 0, "'shortest_path' is empty."
    assert path[0] == "E_VENDOR", f"Expected path to start with 'E_VENDOR', got {path[0]}"
    assert path[-1] == "R_SECURE_PAYMENTS", f"Expected path to end with 'R_SECURE_PAYMENTS', got {path[-1]}"

    graph, _ = load_graph()

    for i in range(len(path) - 1):
        u = path[i]
        v = path[i+1]
        assert v in graph[u], f"Invalid edge in shortest_path: {u} -> {v} does not exist."

    expected_length = compute_shortest_path_length(graph, "E_VENDOR", "R_SECURE_PAYMENTS")
    assert len(path) == expected_length, f"Expected shortest path of length {expected_length} (nodes), but got {len(path)}."

def test_top_grantors_correctness():
    report_path = "/home/user/audit_report.json"
    if not os.path.exists(report_path):
        pytest.fail(f"File {report_path} is missing.")

    with open(report_path, 'r') as f:
        data = json.load(f)

    top_grantors_actual = data.get("top_grantors", [])

    _, out_degree = load_graph()

    sorted_grantors = sorted(out_degree.items(), key=lambda x: (-x[1], x[0]))
    expected_top_3 = [{"emp_id": k, "grants": v} for k, v in sorted_grantors[:3]]

    assert len(top_grantors_actual) == 3, f"Expected exactly 3 top grantors, got {len(top_grantors_actual)}."

    for i in range(3):
        actual = top_grantors_actual[i]
        expected = expected_top_3[i]

        assert "emp_id" in actual, f"Missing 'emp_id' in top_grantors item at index {i}."
        assert "grants" in actual, f"Missing 'grants' in top_grantors item at index {i}."

        assert actual["emp_id"] == expected["emp_id"], f"Expected emp_id {expected['emp_id']} at index {i}, got {actual['emp_id']}."
        assert actual["grants"] == expected["grants"], f"Expected {expected['grants']} grants for {expected['emp_id']}, got {actual['grants']}."
TEST_EOF

run_application() {
    rm -f /home/user/audit_report.json
    chmod 444 /home/user/employees.csv /home/user/access_logs.jsonl
    timeout 90s runuser -u user -- env HOME=/home/user GOCACHE=/tmp/verifier-gocache \
        bash -c 'cd /home/user/workspace && go run .'
}

run_tests() {
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider "$BACKUP_DIR/test_final_state.py" -x --tb=short -q
}

# Execute and validate the application against the original supplied datasets.
if ! run_application || ! run_tests; then
    exit 0
fi
cp -p /home/user/audit_report.json "$ORIGINAL_REPORT"
HAVE_REPORT=1

# Replace the fixture with a runtime-generated valid graph so a hardcoded report
# cannot pass. The existing assertions derive all answers from this graph.
if ! python3 - << 'PY_EOF'
import csv
import json
import random
import secrets

employee_ids = ["E001", "E002", "E003", "E004", "E005", "E006"]
rng = random.SystemRandom()
rng.shuffle(employee_ids)
top_a, top_b, third, bridge = employee_ids[:4]
count = 5 + secrets.randbelow(3)

employees = [
    ["E_VENDOR", "Vendor Acc", "External", "1"],
    ["E001", "Alice", "HR", "2"],
    ["E002", "Bob", "IT", "3"],
    ["E003", "Charlie", "Finance", "4"],
    ["E004", "David", "Engineering", "3"],
    ["E005", "Eve", "Engineering", "5"],
    ["E006", "Frank", "IT", "2"],
]
rng.shuffle(employees)
with open("/home/user/employees.csv", "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(["emp_id", "name", "department", "clearance_level"])
    writer.writerows(employees)

events = []
def add(grantor, field, target):
    events.append({"event_id": f"dyn-{secrets.token_hex(8)}", "grantor_id": grantor, field: target})

add("E_VENDOR", "grantee_id", top_a)
add("E_VENDOR", "grantee_id", bridge)
add(top_a, "resource_id", "R_SECURE_PAYMENTS")
for i in range(count - 1):
    add(top_a, "resource_id", f"R_A_{i}_{secrets.token_hex(3)}")
for i in range(count):
    add(top_b, "resource_id", f"R_B_{i}_{secrets.token_hex(3)}")
for i in range(count - 1):
    add(third, "resource_id", f"R_C_{i}_{secrets.token_hex(3)}")
rng.shuffle(events)
with open("/home/user/access_logs.jsonl", "w") as f:
    for event in events:
        f.write(json.dumps(event) + "\n")
PY_EOF
then
    exit 0
fi

if ! run_application || ! run_tests; then
    exit 0
fi

restore_files
trap - EXIT
echo "1" > /logs/verifier/reward.txt
