#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pytest

def compute_expected_results(metadata_path):
    with open(metadata_path, "r") as f:
        data = json.load(f)

    durations = {}
    adj = {}

    for job in data:
        jid = job["job_id"]
        durations[jid] = job["duration_minutes"]
        adj[jid] = []

    for job in data:
        jid = job["job_id"]
        for dep in job.get("depends_on", []):
            if dep in adj:
                adj[dep].append(jid)

    # Tarjan's algorithm for Strongly Connected Components
    index = 0
    indices = {}
    lowlinks = {}
    stack = []
    on_stack = set()
    sccs = []

    def strongconnect(v):
        nonlocal index
        indices[v] = index
        lowlinks[v] = index
        index += 1
        stack.append(v)
        on_stack.add(v)

        for w in adj[v]:
            if w not in indices:
                strongconnect(w)
                lowlinks[v] = min(lowlinks[v], lowlinks[w])
            elif w in on_stack:
                lowlinks[v] = min(lowlinks[v], indices[w])

        if lowlinks[v] == indices[v]:
            scc = []
            while True:
                w = stack.pop()
                on_stack.remove(w)
                scc.append(w)
                if w == v:
                    break
            sccs.append(scc)

    for v in adj:
        if v not in indices:
            strongconnect(v)

    cyclical_jobs = []
    for scc in sccs:
        if len(scc) > 1:
            cyclical_jobs.extend(scc)

    cyclical_jobs.sort()

    # Filter DAG
    valid_nodes = set(adj.keys()) - set(cyclical_jobs)

    filtered_adj = {v: [] for v in valid_nodes}
    in_degree = {v: 0 for v in valid_nodes}
    for v in valid_nodes:
        for w in adj[v]:
            if w in valid_nodes:
                filtered_adj[v].append(w)
                in_degree[w] += 1

    # Out-degrees
    out_degrees = []
    for v in valid_nodes:
        out_degrees.append((len(filtered_adj[v]), v))

    # Sort by out-degree desc, then alphabetically asc
    out_degrees.sort(key=lambda x: (-x[0], x[1]))
    top_critical_jobs = [x[1] for x in out_degrees[:3]] if len(out_degrees) >= 3 else [x[1] for x in out_degrees]

    # Critical path via topological sort
    queue = [v for v in valid_nodes if in_degree[v] == 0]
    dp = {v: durations[v] for v in valid_nodes}

    max_duration = 0
    if not valid_nodes:
        return cyclical_jobs, top_critical_jobs, 0

    while queue:
        v = queue.pop(0)
        if dp[v] > max_duration:
            max_duration = dp[v]
        for w in filtered_adj[v]:
            if dp[v] + durations[w] > dp[w]:
                dp[w] = dp[v] + durations[w]
            in_degree[w] -= 1
            if in_degree[w] == 0:
                queue.append(w)

    return cyclical_jobs, top_critical_jobs, max_duration

@pytest.fixture
def expected_results():
    metadata_path = "/home/user/backup_metadata.json"
    assert os.path.isfile(metadata_path), f"Input metadata file missing at {metadata_path}"
    return compute_expected_results(metadata_path)

@pytest.fixture
def report_data():
    report_path = "/home/user/report.json"
    assert os.path.isfile(report_path), f"Report file missing at {report_path}"

    with open(report_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Report file at {report_path} is not valid JSON")

    return data

def test_report_structure(report_data):
    expected_keys = {"cyclical_jobs", "top_critical_jobs", "critical_path_duration"}
    assert set(report_data.keys()) == expected_keys, f"Report JSON keys do not match expected structure. Found: {list(report_data.keys())}"

def test_cyclical_jobs(report_data, expected_results):
    expected_cyclical, _, _ = expected_results
    assert isinstance(report_data["cyclical_jobs"], list), "'cyclical_jobs' must be a list"
    assert report_data["cyclical_jobs"] == expected_cyclical, f"Expected cyclical_jobs to be {expected_cyclical}, but got {report_data['cyclical_jobs']}"

def test_top_critical_jobs(report_data, expected_results):
    _, expected_top, _ = expected_results
    assert isinstance(report_data["top_critical_jobs"], list), "'top_critical_jobs' must be a list"
    assert report_data["top_critical_jobs"] == expected_top, f"Expected top_critical_jobs to be {expected_top}, but got {report_data['top_critical_jobs']}"

def test_critical_path_duration(report_data, expected_results):
    _, _, expected_duration = expected_results
    assert isinstance(report_data["critical_path_duration"], (int, float)), "'critical_path_duration' must be a number"
    assert report_data["critical_path_duration"] == expected_duration, f"Expected critical_path_duration to be {expected_duration}, but got {report_data['critical_path_duration']}"
TEST_EOF

status=0
source_path=/home/user/analyze_backups.go
metadata_path=/home/user/backup_metadata.json
report_path=/home/user/report.json
binary_path=/tmp/analyze_backups
original_metadata=/tmp/backup_metadata.original.json

if [[ ! -f "$source_path" || -L "$source_path" ]]; then
    echo "Required Go source file is missing or is not a regular file"
    status=1
elif ! go build -o "$binary_path" "$source_path"; then
    echo "Go program did not compile"
    status=1
elif ! cp "$metadata_path" "$original_metadata"; then
    status=1
else
    cat << 'VARIANT_EOF' > "$metadata_path"
[
  {"job_id":"a","duration_minutes":2,"depends_on":[]},
  {"job_id":"b","duration_minutes":3,"depends_on":["a"]},
  {"job_id":"c","duration_minutes":5,"depends_on":["a"]},
  {"job_id":"d","duration_minutes":7,"depends_on":["b","c"]},
  {"job_id":"e","duration_minutes":11,"depends_on":["d"]},
  {"job_id":"x","duration_minutes":13,"depends_on":["y"]},
  {"job_id":"y","duration_minutes":17,"depends_on":["x"]},
  {"job_id":"z","duration_minutes":19,"depends_on":["x","e"]}
]
VARIANT_EOF

    rm -f "$report_path"
    if ! timeout 30s "$binary_path"; then
        echo "Go program failed on verifier-generated metadata"
        status=1
    elif ! python3 -m pytest /tmp/test_final_state.py -x --tb=short; then
        status=1
    fi

    cp "$original_metadata" "$metadata_path" || status=1
    rm -f "$report_path"
    if ! timeout 30s "$binary_path"; then
        echo "Go program failed on the supplied metadata"
        status=1
    elif ! python3 -m pytest /tmp/test_final_state.py -x --tb=short; then
        status=1
    fi
fi

if [[ "$status" -eq 0 ]]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
