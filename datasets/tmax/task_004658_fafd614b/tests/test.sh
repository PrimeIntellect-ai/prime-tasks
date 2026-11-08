#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import math

def test_processed_logs_exists():
    """Verify that the processed_logs.csv file exists."""
    file_path = '/home/user/processed_logs.csv'
    assert os.path.exists(file_path), f"Output file is missing: {file_path}"
    assert os.path.isfile(file_path), f"Path exists but is not a file: {file_path}"

def test_processed_logs_contents():
    """Verify the contents of processed_logs.csv match the expected aggregated values."""
    file_path = '/home/user/processed_logs.csv'
    assert os.path.exists(file_path), f"Output file is missing: {file_path}"

    with open(file_path, 'r') as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    assert reader.fieldnames == ['user_ip', 'cpu_usage', 'memory_usage'], \
        f"Incorrect columns. Expected ['user_ip', 'cpu_usage', 'memory_usage'], got {reader.fieldnames}"

    expected_data = {
        '10.0.0.0': {'cpu_usage': 38.33, 'memory_usage': 884.0},
        '10.1.1.0': {'cpu_usage': 50.0, 'memory_usage': 1072.0},
        '172.16.0.0': {'cpu_usage': 27.5, 'memory_usage': 578.0},
        '192.168.1.0': {'cpu_usage': 42.5, 'memory_usage': 868.0}
    }

    user_ips = [row['user_ip'] for row in rows]
    assert user_ips == sorted(user_ips), "The CSV is not sorted alphabetically by user_ip"
    assert len(rows) == len(expected_data), f"Expected {len(expected_data)} rows, got {len(rows)}"

    for row in rows:
        ip = row['user_ip']
        assert ip in expected_data, f"Unexpected user_ip found: {ip}"
        expected_cpu = expected_data[ip]['cpu_usage']
        expected_mem = expected_data[ip]['memory_usage']
        actual_cpu = float(row['cpu_usage'])
        actual_mem = float(row['memory_usage'])
        assert math.isclose(actual_cpu, expected_cpu, rel_tol=1e-4), \
            f"For IP {ip}, expected cpu_usage {expected_cpu}, got {actual_cpu}"
        assert math.isclose(actual_mem, expected_mem, rel_tol=1e-4), \
            f"For IP {ip}, expected memory_usage {expected_mem}, got {actual_mem}"

def test_pipeline_log_exists():
    """Verify that the pipeline.log file exists."""
    file_path = '/home/user/pipeline.log'
    assert os.path.exists(file_path), f"Log file is missing: {file_path}"
    assert os.path.isfile(file_path), f"Path exists but is not a file: {file_path}"

def test_pipeline_log_contents_and_order():
    """Verify the pipeline.log contains correct node executions in valid topological order."""
    file_path = '/home/user/pipeline.log'
    assert os.path.exists(file_path), f"Log file is missing: {file_path}"

    with open(file_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    events = []
    for line in lines:
        if line.startswith("[INFO] - Node ") and (" started." in line or " completed." in line):
            parts = line.split(" ")
            node_name = parts[3]
            action = parts[4].replace(".", "")
            events.append({"node": node_name, "action": action})

    required_nodes = {
        "Extract_Telemetry", "Extract_Access", "Impute_Telemetry",
        "Mask_Access", "Merge_And_Aggregate", "Load"
    }

    completed_nodes = set()
    started_nodes = set()
    completion_order = []

    for event in events:
        node = event["node"]
        action = event["action"]

        if action == "started":
            started_nodes.add(node)
            if node == "Impute_Telemetry":
                assert "Extract_Telemetry" in completed_nodes, "Impute_Telemetry started before Extract_Telemetry completed"
            elif node == "Mask_Access":
                assert "Extract_Access" in completed_nodes, "Mask_Access started before Extract_Access completed"
            elif node == "Merge_And_Aggregate":
                assert "Impute_Telemetry" in completed_nodes, "Merge_And_Aggregate started before Impute_Telemetry completed"
                assert "Mask_Access" in completed_nodes, "Merge_And_Aggregate started before Mask_Access completed"
            elif node == "Load":
                assert "Merge_And_Aggregate" in completed_nodes, "Load started before Merge_And_Aggregate completed"

        elif action == "completed":
            assert node in started_nodes, f"Node {node} completed before starting"
            completed_nodes.add(node)
            completion_order.append(node)

    for node in required_nodes:
        assert node in started_nodes, f"Node {node} never started"
        assert node in completed_nodes, f"Node {node} never completed"

    assert completion_order[-1] == "Load", "Load was not the last node to complete"
TEST_EOF

cat << 'DYNAMIC_EOF' > /tmp/test_dynamic.py
import csv
import math
import os
import secrets
import subprocess

rng = secrets.SystemRandom()
base = rng.randrange(20000, 90000)
ca, cb = rng.randrange(31, 61), rng.randrange(71, 101)
cc, cd = rng.randrange(11, 31), rng.randrange(41, 71)
ma, na = rng.randrange(400, 700), rng.randrange(900, 1300)
eb, fb = rng.randrange(1400, 1700), rng.randrange(1800, 2200)

telemetry = [
    [base + 3, 'A', cb, ''],
    [base + 1, 'B', '', eb],
    [base + 0, 'A', '', ma],
    [base + 2, 'B', cd, fb],
    [base + 2, 'A', '', na],
    [base + 0, 'B', cc, ''],
    [base + 4, 'A', '', ''],
    [base + 1, 'A', ca, ''],
]
access = [
    [base + 2, 'A', 'FIRST@Example.COM', '10.23.45.222'],
    [base + 0, 'B', 'second@example.com', '172.20.4.9'],
    [base + 4, 'A', 'third@example.com', '192.168.77.199'],
    [base + 1, 'B', 'fourth@example.com', '10.23.45.17'],
    [base + 0, 'A', 'fifth@example.com', '10.23.45.3'],
    [base + 2, 'B', 'sixth@example.com', '172.20.4.250'],
    [base + 1, 'A', 'seventh@example.com', '192.168.77.8'],
    [base + 99, 'A', 'unmatched@example.com', '8.8.8.8'],
]

with open('/home/user/telemetry.csv', 'w', newline='') as f:
    w = csv.writer(f)
    w.writerow(['timestamp', 'server_id', 'cpu_usage', 'memory_usage'])
    w.writerows(telemetry)
with open('/home/user/access.csv', 'w', newline='') as f:
    w = csv.writer(f)
    w.writerow(['timestamp', 'server_id', 'user_email', 'user_ip'])
    w.writerows(access)

for path in ('/home/user/processed_logs.csv', '/home/user/pipeline.log'):
    try:
        os.remove(path)
    except FileNotFoundError:
        pass

result = subprocess.run(
    ['python3', '/home/user/pipeline.py'], cwd='/home/user',
    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
)
assert result.returncode == 0, f"pipeline.py failed on alternate inputs:\n{result.stdout}\n{result.stderr}"
assert os.path.isfile('/home/user/processed_logs.csv'), 'Pipeline did not create processed_logs.csv'
assert os.path.isfile('/home/user/pipeline.log'), 'Pipeline did not create pipeline.log'

joined = {
    '10.23.45.0': [
        (ca, ma),
        ((ca + cb) / 2.0, na),
        ((cc + cd) / 2.0, eb),
    ],
    '172.20.4.0': [(cc, eb), (cd, fb)],
    '192.168.77.0': [(ca, (ma + na) / 2.0), (cb, na)],
}
expected = {
    ip: (
        round(sum(v[0] for v in values) / len(values), 2),
        round(sum(v[1] for v in values) / len(values), 2),
    )
    for ip, values in joined.items()
}

with open('/home/user/processed_logs.csv', newline='') as f:
    reader = csv.DictReader(f)
    rows = list(reader)
assert reader.fieldnames == ['user_ip', 'cpu_usage', 'memory_usage'], reader.fieldnames
assert [r['user_ip'] for r in rows] == sorted(expected), 'Alternate output is not sorted or has wrong IPs'
assert len(rows) == len(expected), f"Expected {len(expected)} alternate rows, got {len(rows)}"
for row in rows:
    cpu, mem = expected[row['user_ip']]
    assert math.isclose(float(row['cpu_usage']), cpu, rel_tol=1e-9, abs_tol=1e-9), (row, cpu)
    assert math.isclose(float(row['memory_usage']), mem, rel_tol=1e-9, abs_tol=1e-9), (row, mem)

with open('/home/user/pipeline.log') as f:
    lines = [line.strip() for line in f if line.strip()]
events = []
for line in lines:
    if line.startswith('[INFO] - Node ') and (line.endswith(' started.') or line.endswith(' completed.')):
        parts = line.split(' ')
        events.append((parts[3], parts[4].rstrip('.')))
required = {'Extract_Telemetry', 'Extract_Access', 'Impute_Telemetry', 'Mask_Access', 'Merge_And_Aggregate', 'Load'}
started, completed, completion_order = set(), set(), []
for node, action in events:
    if action == 'started':
        if node == 'Impute_Telemetry': assert 'Extract_Telemetry' in completed
        if node == 'Mask_Access': assert 'Extract_Access' in completed
        if node == 'Merge_And_Aggregate':
            assert 'Impute_Telemetry' in completed and 'Mask_Access' in completed
        if node == 'Load': assert 'Merge_And_Aggregate' in completed
        started.add(node)
    elif action == 'completed':
        assert node in started
        completed.add(node)
        completion_order.append(node)
assert required <= started and required <= completed, 'Missing node events on alternate run'
assert completion_order and completion_order[-1] == 'Load', 'Load did not complete last on alternate run'
DYNAMIC_EOF

if [ -f /home/user/pipeline.py ] && [ -s /home/user/pipeline.py ] \
   && rm -f /home/user/processed_logs.csv /home/user/pipeline.log \
   && timeout 30s python3 /home/user/pipeline.py \
   && python3 -m pytest /tmp/test_final_state.py -x --tb=short \
   && python3 /tmp/test_dynamic.py; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
