#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import json
import pytest

DATA_DIR = "/home/user/data"
PACKAGES_CSV = os.path.join(DATA_DIR, "packages.csv")
DEPENDENCIES_CSV = os.path.join(DATA_DIR, "dependencies.csv")
VULNERABILITIES_CSV = os.path.join(DATA_DIR, "vulnerabilities.csv")
OUTPUT_JSON = "/home/user/package_risk.json"

def compute_expected_risk():
    packages = {}
    with open(PACKAGES_CSV, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            packages[row["pkg_id"]] = row["pkg_name"]

    deps = {pid: set() for pid in packages}
    with open(DEPENDENCIES_CSV, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            deps[row["pkg_id"]].add(row["depends_on_pkg_id"])

    vulns = {pid: 0 for pid in packages}
    with open(VULNERABILITIES_CSV, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            vulns[row["pkg_id"]] = int(row["vulnerability_score"])

    def get_transitive_deps(pkg_id):
        visited = set()
        stack = [pkg_id]
        while stack:
            curr = stack.pop()
            for dep in deps.get(curr, []):
                if dep not in visited:
                    visited.add(dep)
                    stack.append(dep)
        return visited

    results = []
    for pid, pname in packages.items():
        all_deps = get_transitive_deps(pid)
        total_risk = vulns[pid] + sum(vulns[dep] for dep in all_deps)
        results.append({
            "pkg_name": pname,
            "total_risk": total_risk
        })

    results.sort(key=lambda x: (-x["total_risk"], x["pkg_name"]))
    return results

def test_output_file_exists():
    assert os.path.isfile(OUTPUT_JSON), f"Expected output file {OUTPUT_JSON} does not exist."

def test_output_json_format_and_values():
    assert os.path.isfile(OUTPUT_JSON), f"Expected output file {OUTPUT_JSON} does not exist."

    with open(OUTPUT_JSON, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{OUTPUT_JSON} is not a valid JSON file.")

    assert isinstance(data, list), f"Output JSON must be a list of objects, got {type(data).__name__}."

    for idx, item in enumerate(data):
        assert isinstance(item, dict), f"Item at index {idx} is not a JSON object."
        assert "pkg_name" in item, f"Item at index {idx} is missing 'pkg_name' key."
        assert "total_risk" in item, f"Item at index {idx} is missing 'total_risk' key."
        assert isinstance(item["pkg_name"], str), f"Item at index {idx} 'pkg_name' is not a string."
        assert isinstance(item["total_risk"], int), f"Item at index {idx} 'total_risk' is not an integer."
        assert len(item.keys()) == 2, f"Item at index {idx} has extra keys."

    expected_data = compute_expected_risk()

    assert len(data) == len(expected_data), f"Expected {len(expected_data)} items in JSON, got {len(data)}."

    for i, (actual, expected) in enumerate(zip(data, expected_data)):
        assert actual == expected, f"Mismatch at index {i}: expected {expected}, got {actual}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
