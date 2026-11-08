#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import json
import tempfile
import pytest
import random
import secrets

EXECUTABLE = "/home/user/sanitiser"
CLEAN_CORPUS = "/app/clean/queries.jsonl"
EVIL_CORPUS = "/app/evil/queries.jsonl"


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} not found."
    assert os.access(EXECUTABLE, os.X_OK), f"{EXECUTABLE} is not executable."


def run_sanitiser(input_file):
    result = subprocess.run([EXECUTABLE, input_file], capture_output=True, text=True)
    return set(result.stdout.strip().split())


def test_clean_corpus():
    assert os.path.isfile(CLEAN_CORPUS), f"Clean corpus missing at {CLEAN_CORPUS}"

    with open(CLEAN_CORPUS, 'r') as f:
        lines = f.read().splitlines()

    failed = []
    for line in lines:
        if not line.strip():
            continue
        data = json.loads(line)
        query_id = data.get("id")

        with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.jsonl') as tmp:
            tmp.write(line + '\n')
            tmp_path = tmp.name

        try:
            output_ids = run_sanitiser(tmp_path)
            if query_id not in output_ids:
                failed.append(query_id)
        finally:
            os.remove(tmp_path)

    assert not failed, f"{len(failed)} of {len(lines)} clean modified/rejected. Offending IDs: {failed}"


def test_evil_corpus():
    assert os.path.isfile(EVIL_CORPUS), f"Evil corpus missing at {EVIL_CORPUS}"

    with open(EVIL_CORPUS, 'r') as f:
        lines = f.read().splitlines()

    failed = []
    for line in lines:
        if not line.strip():
            continue
        data = json.loads(line)
        query_id = data.get("id")

        with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.jsonl') as tmp:
            tmp.write(line + '\n')
            tmp_path = tmp.name

        try:
            output_ids = run_sanitiser(tmp_path)
            if query_id in output_ids:
                failed.append(query_id)
        finally:
            os.remove(tmp_path)

    assert not failed, f"{len(failed)} of {len(lines)} evil bypassed. Offending IDs: {failed}"


def test_bulk_execution():
    clean_output = run_sanitiser(CLEAN_CORPUS)
    evil_output = run_sanitiser(EVIL_CORPUS)

    with open(CLEAN_CORPUS, 'r') as f:
        clean_ids = {json.loads(line)["id"] for line in f if line.strip()}

    with open(EVIL_CORPUS, 'r') as f:
        evil_ids = {json.loads(line)["id"] for line in f if line.strip()}

    missing_clean = clean_ids - clean_output
    bypassed_evil = evil_output.intersection(evil_ids)

    assert not missing_clean, f"Bulk run: missing clean IDs {missing_clean}"
    assert not bypassed_evil, f"Bulk run: bypassed evil IDs {bypassed_evil}"


def path_is_valid(path):
    allowed = {
        ("User", "Bought", "Product"),
        ("User", "Follows", "User"),
        ("Product", "SimilarTo", "Product"),
    }
    if not isinstance(path, list) or len(path) < 1 or len(path) % 2 == 0:
        return False
    if (len(path) - 1) // 2 > 3:
        return False
    if not all(isinstance(part, str) for part in path):
        return False
    return all(tuple(path[i:i + 3]) in allowed for i in range(0, len(path) - 2, 2))


def test_unpredictable_generated_queries():
    # IDs and corpus composition are created only at verification time, so a
    # program cannot pass by printing the IDs from the shipped fixed corpus.
    rng = random.Random(int.from_bytes(secrets.token_bytes(16), "big"))
    prefix = secrets.token_hex(12)
    paths = [
        ["User"],
        ["Product"],
        ["User", "Bought", "Product"],
        ["User", "Follows", "User", "Bought", "Product"],
        ["Product", "SimilarTo", "Product", "SimilarTo", "Product", "SimilarTo", "Product"],
        [],
        ["User", "Bought"],
        ["User", "Bought", "User"],
        ["Product", "Bought", "Product"],
        ["User", "Follows", "Product"],
        ["User", "Follows", "User", "Follows", "User", "Follows", "User", "Follows", "User"],
        ["Unknown"],
        ["User", "UnknownEdge", "Product"],
    ]

    # Generate valid walks of every permitted depth.
    outgoing = {
        "User": [("Bought", "Product"), ("Follows", "User")],
        "Product": [("SimilarTo", "Product")],
    }
    for _ in range(40):
        node = rng.choice(["User", "Product"])
        path = [node]
        for _ in range(rng.randrange(4)):
            edge, node = rng.choice(outgoing[node])
            path.extend([edge, node])
        paths.append(path)

    # Generate arbitrary paths whose answers are computed by the oracle above.
    tokens = ["User", "Product", "Other", "Bought", "Follows", "SimilarTo", "Missing"]
    for _ in range(180):
        paths.append([rng.choice(tokens) for _ in range(rng.randrange(0, 10))])

    records = [
        {"id": f"{prefix}_{i}_{secrets.token_hex(4)}", "path": path}
        for i, path in enumerate(paths)
    ]
    rng.shuffle(records)
    expected = [record["id"] for record in records if path_is_valid(record["path"])]
    assert expected and len(expected) < len(records)

    with tempfile.NamedTemporaryFile(mode="w", delete=False, suffix=".jsonl") as tmp:
        for record in records:
            tmp.write(json.dumps(record) + "\n")
        tmp_path = tmp.name

    try:
        result = subprocess.run(
            [EXECUTABLE, tmp_path], capture_output=True, text=True, timeout=10
        )
    finally:
        os.remove(tmp_path)

    assert result.returncode == 0, f"sanitiser exited with {result.returncode}: {result.stderr}"
    actual = result.stdout.splitlines()
    assert actual == expected, f"generated corpus mismatch: expected {expected}, got {actual}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
