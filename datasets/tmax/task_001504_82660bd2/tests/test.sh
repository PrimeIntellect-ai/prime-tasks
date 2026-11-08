#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import json
import os
import secrets
import stat
import subprocess
import tempfile
from collections import defaultdict

CSV_PATH = "/home/user/edges.csv"
JSON_PATH = "/home/user/aggregated_roles.json"
GO_PATH = "/home/user/graph_pipeline.go"


def expected_from_csv_text(csv_text):
    in_weight = defaultdict(int)
    out_weight = defaultdict(int)
    nodes = set()

    reader = csv.DictReader(io.StringIO(csv_text))
    for row in reader:
        src = row["source"]
        tgt = row["target"]
        weight = int(row["weight"])
        out_weight[src] += weight
        in_weight[tgt] += weight
        nodes.add(src)
        nodes.add(tgt)

    expected = defaultdict(lambda: {"nodes": [], "total_activity": 0})
    for node in nodes:
        iw = in_weight[node]
        ow = out_weight[node]
        activity = iw + ow
        if iw > ow:
            role = "net_sink"
        elif ow > iw:
            role = "net_source"
        else:
            role = "balanced"
        expected[role]["nodes"].append(node)
        expected[role]["total_activity"] += activity

    for role in expected:
        expected[role]["nodes"].sort()
    return expected


def verify_output(csv_text):
    expected = expected_from_csv_text(csv_text)
    assert os.path.exists(JSON_PATH), f"Output file {JSON_PATH} does not exist."

    with open(JSON_PATH, "r") as f:
        try:
            actual = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {JSON_PATH} is not valid JSON."

    for role, data in expected.items():
        assert role in actual, f"Expected role '{role}' is missing in the output JSON."
        actual_nodes = actual[role].get("nodes", [])
        actual_activity = actual[role].get("total_activity", 0)
        assert actual_nodes == data["nodes"], (
            f"Mismatch in nodes for role '{role}'. "
            f"Expected {data['nodes']}, got {actual_nodes}."
        )
        assert actual_activity == data["total_activity"], (
            f"Mismatch in total_activity for role '{role}'. "
            f"Expected {data['total_activity']}, got {actual_activity}."
        )


def run_program(binary):
    if os.path.exists(JSON_PATH):
        os.remove(JSON_PATH)
    result = subprocess.run(
        [binary], cwd="/home/user", capture_output=True, text=True, timeout=15
    )
    assert result.returncode == 0, (
        f"Compiled Go program failed with exit code {result.returncode}. "
        f"stdout: {result.stdout} stderr: {result.stderr}"
    )
    assert os.path.exists(JSON_PATH), (
        f"Running {GO_PATH} did not create {JSON_PATH}."
    )


def make_csv(edges):
    output = io.StringIO()
    writer = csv.writer(output, lineterminator="\n")
    writer.writerow(["source", "target", "weight"])
    writer.writerows(edges)
    return output.getvalue()


def test_go_program_and_aggregated_roles_json():
    assert os.path.exists(GO_PATH), f"Required Go program {GO_PATH} does not exist."
    assert stat.S_ISREG(os.stat(GO_PATH).st_mode), f"{GO_PATH} is not a regular file."

    fd, binary = tempfile.mkstemp(prefix="graph_pipeline_", dir="/tmp")
    os.close(fd)
    os.remove(binary)
    build = subprocess.run(
        ["go", "build", "-o", binary, GO_PATH],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert build.returncode == 0, (
        f"{GO_PATH} is not a buildable Go program. "
        f"stdout: {build.stdout} stderr: {build.stderr}"
    )

    with open(CSV_PATH, "rb") as f:
        original_csv = f.read()

    token = secrets.token_hex(6)
    w = secrets.randbelow(700) + 101
    p = secrets.randbelow(500) + 201
    r = secrets.randbelow(p - 1) + 1
    q = secrets.randbelow(400) + 51
    b = secrets.randbelow(300) + 11

    dynamic_cases = [
        make_csv([
            (f"S_{token}", f"T_{token}", w),
            (f"B_{token}", f"B_{token}", b),
            (f"X_{token}", f"Y_{token}", p),
            (f"Z_{token}", f"Y_{token}", q),
            (f"Y_{token}", f"X_{token}", r),
        ]),
        make_csv([
            (f"A_{token}", f"C_{token}", w),
            (f"C_{token}", f"D_{token}", w),
            (f"D_{token}", f"A_{token}", w),
            (f"M_{token}", f"N_{token}", q),
        ]),
    ]

    try:
        for csv_text in dynamic_cases:
            with open(CSV_PATH, "w", newline="") as f:
                f.write(csv_text)
            run_program(binary)
            verify_output(csv_text)
    finally:
        with open(CSV_PATH, "wb") as f:
            f.write(original_csv)

    original_text = original_csv.decode("utf-8")
    run_program(binary)
    verify_output(original_text)


TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
