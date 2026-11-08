#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import copy
import json
import os
import secrets
import subprocess
import tempfile
import pytest


def test_part1_malicious_session_extracted():
    output_file = "/home/user/malicious_session.txt"
    assert os.path.exists(output_file), f"Output file missing: {output_file}"

    with open(output_file, "r") as f:
        content = f.read().strip()

    expected_session_id = "77B-XYZ-912"
    assert content == expected_session_id, f"Extracted session ID is incorrect. Expected '{expected_session_id}', got '{content}'"


def test_part2_query_auditor_script_exists_and_executable():
    script_path = "/home/user/query_auditor.sh"
    assert os.path.exists(script_path), f"Script missing: {script_path}"
    assert os.path.isfile(script_path), f"Path is not a file: {script_path}"
    assert os.access(script_path, os.X_OK), f"Script is not executable: {script_path}"


def test_part2_query_auditor_clean_corpus():
    script_path = "/home/user/query_auditor.sh"
    clean_dir = "/app/corpus/clean"

    assert os.path.exists(clean_dir), f"Clean corpus directory missing: {clean_dir}"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith(".json")]
    assert len(clean_files) > 0, "No clean corpus files found"

    failed_clean = []
    for cf in clean_files:
        result = subprocess.run([script_path, cf], capture_output=True)
        if result.returncode != 0:
            failed_clean.append(os.path.basename(cf))

    if failed_clean:
        pytest.fail(f"{len(failed_clean)} of {len(clean_files)} clean files rejected (should be accepted/exit 0): {', '.join(failed_clean)}")


def test_part2_query_auditor_evil_corpus():
    script_path = "/home/user/query_auditor.sh"
    evil_dir = "/app/corpus/evil"

    assert os.path.exists(evil_dir), f"Evil corpus directory missing: {evil_dir}"

    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith(".json")]
    assert len(evil_files) > 0, "No evil corpus files found"

    failed_evil = []
    for ef in evil_files:
        result = subprocess.run([script_path, ef], capture_output=True)
        if result.returncode == 0:
            failed_evil.append(os.path.basename(ef))

    if failed_evil:
        pytest.fail(f"{len(failed_evil)} of {len(evil_files)} evil files bypassed (should be rejected/exit 1): {', '.join(failed_evil)}")


def reference_compliant(pipeline):
    if not isinstance(pipeline, list) or not pipeline:
        return False
    first = pipeline[0]
    if not isinstance(first, dict):
        return False
    match = first.get("$match")
    if not isinstance(match, dict) or "tenant_id" not in match:
        return False
    for stage in pipeline:
        if not isinstance(stage, dict):
            continue
        lookup = stage.get("$lookup")
        if isinstance(lookup, dict) and lookup.get("from") == "system.users":
            return False
    return True


def test_part2_generated_holdout_queries():
    script_path = "/home/user/query_auditor.sh"
    cases = []

    for i in range(10):
        token = secrets.token_hex(8)
        tenant = f"TENANT-{token}"
        base = [
            {"$match": {"tenant_id": tenant, f"field_{token}": f"value_{token}"}},
            {"$project": {f"field_{token}": 1, "_id": 0}},
        ]
        if i % 2 == 0:
            base.append({"$lookup": {
                "from": "orders",
                "localField": f"local_{token}",
                "foreignField": f"foreign_{token}",
                "as": f"joined_{token}",
            }})
        cases.append(base)

        missing_tenant = copy.deepcopy(base)
        del missing_tenant[0]["$match"]["tenant_id"]
        cases.append(missing_tenant)

        late_match = copy.deepcopy(base)
        late_match.insert(0, {"$sort": {f"created_{token}": -1}})
        cases.append(late_match)

        restricted_lookup = copy.deepcopy(base)
        restricted_lookup.append({"$lookup": {
            "from": "system.users",
            "localField": f"local_{token}",
            "foreignField": f"foreign_{token}",
            "as": f"restricted_{token}",
        }})
        cases.append(restricted_lookup)

    expected_results = [0 if reference_compliant(case) else 1 for case in cases]
    assert 0 in expected_results and 1 in expected_results

    failures = []
    with tempfile.TemporaryDirectory(prefix="query_holdout_") as holdout_dir:
        for index, (pipeline, expected) in enumerate(zip(cases, expected_results)):
            path = os.path.join(holdout_dir, f"case_{secrets.token_hex(10)}.json")
            with open(path, "w") as f:
                json.dump(pipeline, f, separators=(",", ":"))

            try:
                result = subprocess.run(
                    [script_path, path],
                    capture_output=True,
                    timeout=5,
                )
            except subprocess.TimeoutExpired:
                failures.append(f"case {index}: timed out")
                continue

            if result.returncode != expected:
                failures.append(
                    f"case {index}: expected exit {expected}, got {result.returncode}"
                )

    if failures:
        pytest.fail("Generated holdout failures: " + "; ".join(failures))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
