#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import csv
from collections import defaultdict

def test_go_files_exist():
    """Verify that the Go program and module file exist."""
    assert os.path.isfile("/home/user/audit.go"), "The file /home/user/audit.go is missing."
    assert os.path.isfile("/home/user/go.mod"), "The Go module file /home/user/go.mod is missing. Did you run 'go mod init'?"

def test_compliance_report_json():
    """Verify that the compliance report is generated correctly according to the rules."""
    report_path = "/home/user/compliance_report.json"
    assert os.path.isfile(report_path), f"The file {report_path} is missing."

    with open(report_path, "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            assert False, f"The file {report_path} is not valid JSON."

    assert "centrality" in report, "Missing 'centrality' key in the compliance report."
    assert "unauthorized_accesses" in report, "Missing 'unauthorized_accesses' key in the compliance report."

    # Recompute the expected results from the CSVs
    graph_path = "/home/user/data/graph.csv"
    logs_path = "/home/user/data/logs.csv"

    assert os.path.isfile(graph_path), "graph.csv is missing."
    assert os.path.isfile(logs_path), "logs.csv is missing."

    user_roles = defaultdict(set)
    role_systems = defaultdict(set)
    users = set()

    with open(graph_path, "r") as f:
        reader = csv.reader(f)
        for row in reader:
            if len(row) == 3:
                subj, pred, obj = row
                if pred == "type" and obj == "User":
                    users.add(subj)
                elif pred == "assigned_to":
                    user_roles[subj].add(obj)
                elif pred == "grants_access":
                    role_systems[subj].add(obj)

    expected_centrality = {}
    user_authorized_systems = defaultdict(set)
    for u in users:
        auth_sys = set()
        for r in user_roles.get(u, []):
            auth_sys.update(role_systems.get(r, []))
        expected_centrality[u] = len(auth_sys)
        user_authorized_systems[u] = auth_sys

    assert report["centrality"] == expected_centrality, f"Centrality mismatch. Expected {expected_centrality}, but got {report['centrality']}."

    unauth_counts = defaultdict(int)
    with open(logs_path, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            u = row.get("user_id")
            s = row.get("system_id")
            if u and s:
                if s not in user_authorized_systems.get(u, set()):
                    unauth_counts[(u, s)] += 1

    expected_unauth = []
    for (u, s), count in sorted(unauth_counts.items()):
        expected_unauth.append({"user_id": u, "system_id": s, "count": count})

    assert report["unauthorized_accesses"] == expected_unauth, f"Unauthorized accesses mismatch. Expected {expected_unauth}, but got {report['unauthorized_accesses']}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
