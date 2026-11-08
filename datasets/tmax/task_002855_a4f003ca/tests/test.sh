#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import subprocess
import glob
import secrets
import tempfile
import uuid
import pytest

SCRIPT_PATH = "/home/user/analyze_pipelines.py"

def run_script(input_file, output_file):
    if not os.path.exists(SCRIPT_PATH):
        return False, "Script not found"

    try:
        subprocess.run(
            ["python3", SCRIPT_PATH, input_file, output_file],
            check=True,
            capture_output=True,
            text=True,
            timeout=15
        )
        return True, ""
    except subprocess.TimeoutExpired:
        return False, "Script timed out"
    except subprocess.CalledProcessError as e:
        return False, f"Script failed: {e.stderr}"

def test_script_exists():
    assert os.path.exists(SCRIPT_PATH), f"{SCRIPT_PATH} is missing."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."

def test_evil_corpus():
    evil_files = glob.glob("/app/corpus/evil/*.json")
    assert evil_files, "Evil corpus is missing or empty."

    bypassed = []
    for evil_file in evil_files:
        output_file = evil_file + ".out"
        success, err = run_script(evil_file, output_file)
        if not success:
            bypassed.append(f"{os.path.basename(evil_file)} (Execution failed: {err})")
            continue

        try:
            with open(output_file, 'r') as f:
                output_data = json.load(f)
            if output_data != []:
                bypassed.append(os.path.basename(evil_file))
        except Exception:
            bypassed.append(f"{os.path.basename(evil_file)} (Invalid JSON output)")

    assert not bypassed, f"{len(bypassed)} of {len(evil_files)} evil bypassed: {', '.join(bypassed)}"

def test_clean_corpus():
    clean_files = glob.glob("/app/corpus/clean/*.json")
    assert clean_files, "Clean corpus is missing or empty."

    modified = []
    for clean_file in clean_files:
        output_file = clean_file + ".out"
        success, err = run_script(clean_file, output_file)
        if not success:
            modified.append(f"{os.path.basename(clean_file)} (Execution failed: {err})")
            continue

        try:
            with open(clean_file, 'r') as f:
                input_data = json.load(f)
            with open(output_file, 'r') as f:
                output_data = json.load(f)
            if output_data != input_data:
                modified.append(os.path.basename(clean_file))
        except Exception:
            modified.append(f"{os.path.basename(clean_file)} (Invalid JSON output)")

    assert not modified, f"{len(modified)} of {len(clean_files)} clean modified: {', '.join(modified)}"

def is_safe(pipeline):
    if not pipeline or not isinstance(pipeline[-1], dict):
        return True

    merge_spec = pipeline[-1].get("$merge")
    if not isinstance(merge_spec, dict) or merge_spec.get("into") != "ledger":
        return True

    before_merge = pipeline[:-1]
    has_tenant_match = any(
        isinstance(stage, dict)
        and isinstance(stage.get("$match"), dict)
        and "tenant_id" in stage["$match"]
        for stage in before_merge
    )
    has_required_sort = any(
        isinstance(stage, dict)
        and stage.get("$sort") == {"transaction_date": -1}
        for stage in before_merge
    )
    return has_tenant_match and has_required_sort

def make_hidden_batch(rng):
    token = uuid.uuid4().hex
    tenant = rng.randrange(1, 10**9)
    amount = rng.randrange(1, 100000)

    safe_ledger = [
        {"$match": {"tenant_id": tenant, "state": {"$in": [token, "posted"]}}},
        {"$project": {"tenant_id": 1, "transaction_date": 1, token: 1}},
        {"$sort": {"transaction_date": -1}},
        {"$merge": {"into": "ledger"}}
    ]
    safe_ledger_with_filler = [
        {"$match": {"tenant_id": {"$eq": tenant}}},
        {"$limit": rng.randrange(1, 100)},
        {"$sort": {"transaction_date": -1}},
        {"$merge": {"into": "ledger"}}
    ]
    missing_match = [
        {"$match": {"account_id": token}},
        {"$sort": {"transaction_date": -1}},
        {"$merge": {"into": "ledger"}}
    ]
    missing_sort = [
        {"$match": {"tenant_id": tenant, "amount": {"$gte": amount}}},
        {"$project": {"amount": 1}},
        {"$merge": {"into": "ledger"}}
    ]
    wrong_sort = [
        {"$match": {"tenant_id": tenant}},
        {"$sort": {"transaction_date": 1}},
        {"$merge": {"into": "ledger"}}
    ]
    unrelated_merge = [
        {"$match": {"account_id": token}},
        {"$merge": {"into": "archive_" + token[:8]}}
    ]
    ordinary_pipeline = [
        {"$match": {"region": token[:6]}},
        {"$group": {"_id": "$region", "total": {"$sum": "$amount"}}},
        {"$sort": {"total": -1}}
    ]

    batch = [
        safe_ledger,
        safe_ledger_with_filler,
        missing_match,
        missing_sort,
        wrong_sort,
        unrelated_merge,
        ordinary_pipeline,
    ]
    rng.shuffle(batch)
    return batch

def test_generated_hidden_batches():
    rng = secrets.SystemRandom()
    with tempfile.TemporaryDirectory() as td:
        for _ in range(8):
            batch = make_hidden_batch(rng)
            expected = [pipeline for pipeline in batch if is_safe(pipeline)]
            input_file = os.path.join(td, uuid.uuid4().hex + ".json")
            output_file = os.path.join(td, uuid.uuid4().hex + ".json")

            with open(input_file, "w") as f:
                json.dump(batch, f)

            success, err = run_script(input_file, output_file)
            assert success, err
            assert os.path.exists(output_file), "Script did not create the requested output file."

            try:
                with open(output_file, "r") as f:
                    actual = json.load(f)
            except Exception as exc:
                pytest.fail(f"Generated-case output is not valid JSON: {exc}")

            assert actual == expected, "Generated pipelines were not filtered or preserved correctly."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
