#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import pytest

def compute_expected_summary(input_path):
    data = []
    with open(input_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            data.append({
                'timestamp': int(row['timestamp']),
                'server_id': row['server_id'],
                'cpu_temp': float(row['cpu_temp']) if row['cpu_temp'] else None,
                'latency_ms': float(row['latency_ms']) if row['latency_ms'] else None
            })

    servers = {}
    for row in data:
        servers.setdefault(row['server_id'], []).append(row)

    expected_summary = {}
    for srv, records in servers.items():
        records.sort(key=lambda x: x['timestamp'])

        for i, rec in enumerate(records):
            if rec['cpu_temp'] is None:
                prev_idx = i - 1
                while prev_idx >= 0 and records[prev_idx]['cpu_temp'] is None:
                    prev_idx -= 1

                next_idx = i + 1
                while next_idx < len(records) and records[next_idx]['cpu_temp'] is None:
                    next_idx += 1

                prev_rec = records[prev_idx]
                next_rec = records[next_idx]
                time_diff = next_rec['timestamp'] - prev_rec['timestamp']
                temp_diff = next_rec['cpu_temp'] - prev_rec['cpu_temp']
                rec['cpu_temp'] = prev_rec['cpu_temp'] + temp_diff * ((rec['timestamp'] - prev_rec['timestamp']) / time_diff)

        valid_lats = [r['latency_ms'] for r in records if r['latency_ms'] is not None]
        mean_lat = sum(valid_lats) / len(valid_lats) if valid_lats else 0.0

        for rec in records:
            if rec['latency_ms'] is None:
                rec['latency_ms'] = mean_lat

        max_temp = max(r['cpu_temp'] for r in records)
        avg_latency = sum(r['latency_ms'] for r in records) / len(records)
        overheat_events = sum(1 for r in records if r['cpu_temp'] > 85.0)

        expected_summary[srv] = {
            'max_temp': f"{max_temp:.2f}",
            'avg_latency': f"{avg_latency:.2f}",
            'overheat_events': str(overheat_events)
        }

    return expected_summary

def test_server_summary_exists():
    path = "/home/user/server_summary.csv"
    assert os.path.exists(path), f"Output file {path} was not created."
    assert os.path.isfile(path), f"{path} is not a file."

def test_server_summary_contents():
    input_path = "/home/user/sensor_logs.csv"
    output_path = "/home/user/server_summary.csv"
    expected_summary = compute_expected_summary(input_path)

    actual_data = []
    with open(output_path, 'r') as f:
        reader = csv.DictReader(f)
        actual_headers = reader.fieldnames
        for row in reader:
            actual_data.append(row)

    expected_headers = ['server_id', 'max_temp', 'avg_latency', 'overheat_events']
    assert actual_headers == expected_headers, f"Expected headers {expected_headers}, but got {actual_headers}"

    actual_servers = [row['server_id'] for row in actual_data]
    assert actual_servers == sorted(actual_servers), "The rows in the output CSV are not sorted alphabetically by server_id."
    assert len(actual_data) == len(expected_summary), f"Expected {len(expected_summary)} rows, but got {len(actual_data)}"

    for row in actual_data:
        srv = row['server_id']
        assert srv in expected_summary, f"Unexpected server_id {srv} in output."
        expected = expected_summary[srv]
        assert row['max_temp'] == expected['max_temp'], f"For server {srv}, expected max_temp {expected['max_temp']}, got {row['max_temp']}"
        assert row['avg_latency'] == expected['avg_latency'], f"For server {srv}, expected avg_latency {expected['avg_latency']}, got {row['avg_latency']}"
        assert row['overheat_events'] == expected['overheat_events'], f"For server {srv}, expected overheat_events {expected['overheat_events']}, got {row['overheat_events']}"
TEST_EOF

cat << 'GO_EOF' > /tmp/check_goroutine.go
package main

import (
    "fmt"
    "go/ast"
    "go/parser"
    "go/token"
    "os"
)

func main() {
    if len(os.Args) != 2 {
        os.Exit(2)
    }
    f, err := parser.ParseFile(token.NewFileSet(), os.Args[1], nil, 0)
    if err != nil {
        fmt.Fprintln(os.Stderr, err)
        os.Exit(1)
    }
    found := false
    ast.Inspect(f, func(n ast.Node) bool {
        if _, ok := n.(*ast.GoStmt); ok {
            found = true
        }
        return true
    })
    if !found {
        fmt.Fprintln(os.Stderr, "analyze.go contains no goroutine launch")
        os.Exit(1)
    }
}
GO_EOF

backup=/tmp/sensor_logs.csv.original
restore_input() {
    if [ -f "$backup" ]; then
        cp "$backup" /home/user/sensor_logs.csv
    fi
}

run_checks() {
    test -f /home/user/analyze.go || return 1
    cp /home/user/sensor_logs.csv "$backup" || return 1

    go build -o /tmp/check_goroutine /tmp/check_goroutine.go || return 1
    /tmp/check_goroutine /home/user/analyze.go || return 1
    go build -o /tmp/analyze_submission /home/user/analyze.go || return 1

    rm -f /home/user/server_summary.csv
    (cd /home/user && timeout 30s /tmp/analyze_submission) || return 1
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short || return 1

    python3 - << 'PY_EOF' || return 1
import csv
import random
import secrets

rng = random.Random(secrets.randbits(128))
rows = []
servers = ['NODE-Z', 'NODE-A', 'NODE-M', 'NODE-Q']
for sidx, server in enumerate(servers):
    timestamps = sorted(rng.sample(range(1700000000, 1700010000), 17))
    for i, ts in enumerate(timestamps):
        temp = 72.0 + sidx * 4.5 + rng.uniform(-6.0, 13.0)
        latency = 20.0 + sidx * 31.0 + rng.uniform(-8.0, 25.0)
        temp_text = f'{temp:.2f}'
        lat_text = f'{latency:.2f}'
        if i not in (0, len(timestamps) - 1) and (i in (3, 4, 10) or rng.random() < 0.18):
            temp_text = ''
        if i in (2, 8, 9) or rng.random() < 0.16:
            lat_text = ''
        rows.append({
            'timestamp': ts,
            'server_id': server,
            'cpu_temp': temp_text,
            'memory_mb': rng.randint(1024, 32768),
            'latency_ms': lat_text,
        })
rng.shuffle(rows)
with open('/home/user/sensor_logs.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=['timestamp', 'server_id', 'cpu_temp', 'memory_mb', 'latency_ms'])
    writer.writeheader()
    writer.writerows(rows)
PY_EOF

    rm -f /home/user/server_summary.csv
    (cd /home/user && timeout 30s /tmp/analyze_submission) || return 1
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short || return 1
}

run_checks
status=$?
restore_input

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
