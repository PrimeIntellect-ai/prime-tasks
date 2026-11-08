#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import copy
import json
import os
import secrets
import subprocess
import pytest

VALIDATOR_PATH = "/home/user/validator"
SOURCE_PATH = "/home/user/validator.cpp"
COMPILED_SOURCE_PATH = "/tmp/validator_from_submitted_source"
CLEAN_CORPUS_DIR = "/app/corpora/clean"
EVIL_CORPUS_DIR = "/app/corpora/evil"


def run_validator(path, payload, timeout=2):
    try:
        return subprocess.run(
            [path],
            input=payload,
            text=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=timeout,
        ).returncode
    except subprocess.TimeoutExpired:
        pytest.fail(f"Validator {path} timed out")


def test_validator_exists_and_executable():
    assert os.path.isfile(VALIDATOR_PATH), f"Validator executable not found at {VALIDATOR_PATH}"
    assert os.access(VALIDATOR_PATH, os.X_OK), f"Validator at {VALIDATOR_PATH} is not executable"
    with open(VALIDATOR_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Validator must be a compiled ELF executable"


def test_cpp_source_exists():
    assert os.path.isfile(SOURCE_PATH), f"C++ source not found at {SOURCE_PATH}"
    assert os.path.getsize(SOURCE_PATH) > 0, f"C++ source at {SOURCE_PATH} is empty"


@pytest.fixture(scope="session")
def compiled_source():
    assert os.path.isfile(SOURCE_PATH), f"C++ source not found at {SOURCE_PATH}"
    try:
        os.unlink(COMPILED_SOURCE_PATH)
    except FileNotFoundError:
        pass
    result = subprocess.run(
        ["g++", "-x", "c++", "-std=c++17", "-O2", SOURCE_PATH, "-o", COMPILED_SOURCE_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"Submitted C++ source does not compile:\n{result.stderr}"
    assert os.path.isfile(COMPILED_SOURCE_PATH)
    assert os.access(COMPILED_SOURCE_PATH, os.X_OK)
    return COMPILED_SOURCE_PATH


def test_clean_corpus():
    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith('.json')]
    assert len(clean_files) > 0, f"No JSON files found in {CLEAN_CORPUS_DIR}"

    failed_files = []
    for filename in clean_files:
        filepath = os.path.join(CLEAN_CORPUS_DIR, filename)
        with open(filepath, 'r') as f:
            result = subprocess.run([VALIDATOR_PATH], stdin=f, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if result.returncode != 0:
                failed_files.append(filename)

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean files rejected (should exit 0): {', '.join(failed_files)}")


def test_evil_corpus():
    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith('.json')]
    assert len(evil_files) > 0, f"No JSON files found in {EVIL_CORPUS_DIR}"

    failed_files = []
    for filename in evil_files:
        filepath = os.path.join(EVIL_CORPUS_DIR, filename)
        with open(filepath, 'r') as f:
            result = subprocess.run([VALIDATOR_PATH], stdin=f, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if result.returncode == 0:
                failed_files.append(filename)

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil files bypassed (should exit 1): {', '.join(failed_files)}")


def make_dynamic_cases():
    token = secrets.token_hex(12)
    accepted = []
    rejected = []

    # Valid records deliberately use both formerly "clean" and "evil" prefixes.
    for i in range(12):
        prefix = "e" if i % 2 == 0 else "p"
        path_id = f"{prefix}-hidden-{token}-{i}"
        cost = secrets.randbelow(5001)
        nodes = [f"NODE-{token}-{i}", "proxy-99", "PROXY-990"] if i % 3 else []
        valid = {
            "schema_version": "2.0",
            "path_id": path_id,
            "nodes": nodes,
            "total_cost": cost,
        }
        accepted.append(json.dumps(valid, separators=(",", ":")))

        forbidden = copy.deepcopy(valid)
        forbidden["nodes"] = list(forbidden["nodes"]) + ["PROXY-99"]
        rejected.append(json.dumps(forbidden, separators=(",", ":")))

        costly = copy.deepcopy(valid)
        costly["total_cost"] = 5001 + secrets.randbelow(100000)
        rejected.append(json.dumps(costly, separators=(",", ":")))

    edge_id = f"edge-{token}"
    accepted.extend([
        json.dumps({"schema_version": "2.0", "path_id": edge_id, "nodes": [], "total_cost": 5000}),
        json.dumps({"schema_version": "2.0", "path_id": edge_id, "nodes": ["PROXY-99-extra"], "total_cost": -17}),
        json.dumps({"schema_version": "2.0", "path_id": "", "nodes": ["A", "Ω"], "total_cost": 0}),
    ])

    base = {"schema_version": "2.0", "path_id": edge_id, "nodes": ["A"], "total_cost": 42}

    for field in list(base):
        bad = copy.deepcopy(base)
        del bad[field]
        rejected.append(json.dumps(bad))

    bad = copy.deepcopy(base)
    bad["unexpected"] = "field"
    rejected.append(json.dumps(bad))

    replacements = {
        "schema_version": ["2", "2.00", 2, None, True],
        "path_id": [7, None, True, ["id"], {"id": "x"}],
        "nodes": ["A", None, True, {"0": "A"}, ["A", 2], [None], [True]],
        "total_cost": [5000.0, "42", None, True, [], {}],
    }
    for field, values in replacements.items():
        for value in values:
            bad = copy.deepcopy(base)
            bad[field] = value
            rejected.append(json.dumps(bad))

    rejected.extend([
        "",
        "not json",
        "{",
        "[]",
        "null",
        json.dumps(base) + " trailing-data",
        '{"schema_version":"2.0","path_id":"x","nodes":["A"],"total_cost":}',
    ])
    return accepted, rejected


def test_generated_schema_and_business_rules(compiled_source):
    accepted, rejected = make_dynamic_cases()

    # Exercise both the submitted executable and an executable independently
    # built as C++ from the submitted validator.cpp.
    for executable in (VALIDATOR_PATH, compiled_source):
        for payload in accepted:
            rc = run_validator(executable, payload + "\n")
            assert rc == 0, f"{executable} rejected a generated valid record (exit {rc}): {payload}"

        for payload in rejected:
            rc = run_validator(executable, payload + "\n")
            assert rc == 1, f"{executable} did not reject a generated invalid record with exit 1 (exit {rc}): {payload}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
