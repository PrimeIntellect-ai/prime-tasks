#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import glob
import random
import secrets
import subprocess
import tempfile
from collections import defaultdict, deque

import pytest
import yaml

CONFIG_PATH = "/home/user/app_config.yaml"
SOURCE_PATH = "/home/user/validator.cpp"
BINARY_PATH = "/home/user/validate_queries"


def run_validator(binary, csv_path):
    try:
        return subprocess.run(
            [binary, csv_path], capture_output=True, text=True, timeout=5
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Validator timed out on {csv_path}")


def test_app_config_yaml():
    assert os.path.exists(CONFIG_PATH), f"Configuration file {CONFIG_PATH} does not exist."

    with open(CONFIG_PATH, "r") as f:
        try:
            config = yaml.safe_load(f)
        except yaml.YAMLError as e:
            pytest.fail(f"Failed to parse {CONFIG_PATH} as YAML: {e}")

    assert isinstance(config, dict), f"{CONFIG_PATH} does not contain a valid YAML dictionary."
    assert config.get("lock_manager_host") == "127.0.0.1", "lock_manager_host is not set to '127.0.0.1'"
    assert config.get("lock_manager_port") == 8001, "lock_manager_port is not set to 8001"
    assert config.get("validator_binary") == BINARY_PATH, "validator_binary is not set to '/home/user/validate_queries'"


def test_validator_binary_exists():
    assert os.path.exists(BINARY_PATH), f"Validator binary {BINARY_PATH} does not exist."
    assert os.path.isfile(BINARY_PATH), f"Validator binary {BINARY_PATH} is not a regular file."
    assert os.access(BINARY_PATH, os.X_OK), f"Validator binary {BINARY_PATH} is not executable."
    with open(BINARY_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Validator binary {BINARY_PATH} is not a compiled ELF executable."


def test_validator_source_compiles_as_cpp17(tmp_path):
    assert os.path.exists(SOURCE_PATH), f"Validator source {SOURCE_PATH} does not exist."
    assert os.path.isfile(SOURCE_PATH), f"Validator source {SOURCE_PATH} is not a regular file."
    rebuilt = tmp_path / "rebuilt_validator"
    result = subprocess.run(
        ["g++", "-std=c++17", "-O2", SOURCE_PATH, "-o", str(rebuilt)],
        capture_output=True, text=True, timeout=30
    )
    assert result.returncode == 0, f"validator.cpp does not compile with C++17:\n{result.stderr}"
    with open(rebuilt, "rb") as f:
        assert f.read(4) == b"\x7fELF"


def test_validator_against_corpora():
    clean_dir = "/home/user/corpus/clean"
    evil_dir = "/home/user/corpus/evil"

    clean_csvs = glob.glob(os.path.join(clean_dir, "*.csv"))
    evil_csvs = glob.glob(os.path.join(evil_dir, "*.csv"))

    assert len(clean_csvs) > 0, f"No CSV files found in {clean_dir}."
    assert len(evil_csvs) > 0, f"No CSV files found in {evil_dir}."

    failed_clean = []
    for csv_file in clean_csvs:
        result = run_validator(BINARY_PATH, csv_file)
        if result.returncode != 0 or result.stdout.strip() != "ACCEPT":
            failed_clean.append(os.path.basename(csv_file))

    failed_evil = []
    for csv_file in evil_csvs:
        result = run_validator(BINARY_PATH, csv_file)
        if result.returncode != 1 or result.stdout.strip() != "REJECT":
            failed_evil.append(os.path.basename(csv_file))

    error_messages = []
    if failed_clean:
        error_messages.append(f"{len(failed_clean)} of {len(clean_csvs)} clean modified/rejected: {', '.join(failed_clean)}")
    if failed_evil:
        error_messages.append(f"{len(failed_evil)} of {len(evil_csvs)} evil bypassed/accepted: {', '.join(failed_evil)}")
    if error_messages:
        pytest.fail(" | ".join(error_messages))


def oracle(events):
    owners = {}
    waiters = defaultdict(deque)

    def has_cycle():
        graph = defaultdict(set)
        vertices = set()
        for resource, queue in waiters.items():
            owner = owners.get(resource)
            if owner is None:
                continue
            vertices.add(owner)
            for waiter in queue:
                graph[waiter].add(owner)
                vertices.add(waiter)

        color = {}
        def visit(node):
            color[node] = 1
            for nxt in graph[node]:
                if color.get(nxt, 0) == 1:
                    return True
                if color.get(nxt, 0) == 0 and visit(nxt):
                    return True
            color[node] = 2
            return False

        return any(color.get(v, 0) == 0 and visit(v) for v in vertices)

    for tx, resource, action in events:
        if action == "ACQUIRE":
            if resource not in owners:
                owners[resource] = tx
            elif owners[resource] != tx and tx not in waiters[resource]:
                waiters[resource].append(tx)
        else:
            if owners.get(resource) == tx:
                if waiters[resource]:
                    owners[resource] = waiters[resource].popleft()
                else:
                    owners.pop(resource, None)
        if has_cycle():
            return "REJECT", 1
    return "ACCEPT", 0


def renamed_template(template, rng):
    tx_names = {}
    resource_names = {}
    result = []
    for tx, resource, action in template:
        tx_names.setdefault(tx, "TX_" + secrets.token_hex(6))
        resource_names.setdefault(resource, "RES_" + secrets.token_hex(6))
        result.append((tx_names[tx], resource_names[resource], action))
    return result


def generated_cases():
    rng = random.SystemRandom()
    templates = [
        [("A", "X", "ACQUIRE"), ("A", "X", "RELEASE")],
        [("A", "X", "ACQUIRE"), ("B", "X", "ACQUIRE"), ("C", "X", "ACQUIRE"),
         ("A", "X", "RELEASE"), ("B", "X", "RELEASE"), ("C", "X", "RELEASE")],
        [("A", "X", "ACQUIRE"), ("B", "Y", "ACQUIRE"), ("C", "Z", "ACQUIRE"),
         ("B", "X", "ACQUIRE"), ("C", "Y", "ACQUIRE")],
        [("A", "X", "ACQUIRE"), ("B", "Y", "ACQUIRE"),
         ("A", "Y", "ACQUIRE"), ("B", "X", "ACQUIRE")],
        [("A", "X", "ACQUIRE"), ("B", "Y", "ACQUIRE"), ("C", "Z", "ACQUIRE"),
         ("A", "Y", "ACQUIRE"), ("B", "Z", "ACQUIRE"), ("C", "X", "ACQUIRE")],
        # The final RELEASE transfers X to B and changes C's dependency to B,
        # forming B -> C -> B. This checks FIFO transfer and graph maintenance.
        [("C", "T", "ACQUIRE"), ("A", "X", "ACQUIRE"), ("B", "X", "ACQUIRE"),
         ("C", "X", "ACQUIRE"), ("B", "T", "ACQUIRE"), ("A", "X", "RELEASE")],
        # A cycle must be reported immediately even though later lines could release it.
        [("A", "X", "ACQUIRE"), ("B", "Y", "ACQUIRE"), ("A", "Y", "ACQUIRE"),
         ("B", "X", "ACQUIRE"), ("A", "X", "RELEASE"), ("B", "Y", "RELEASE")],
    ]

    cases = [renamed_template(t, rng) for t in templates]
    # Create additional unpredictable, valid lock streams and derive their answers
    # independently. Keep examples from both classifications.
    wanted = {"ACCEPT": 10, "REJECT": 10}
    found = {"ACCEPT": 0, "REJECT": 0}
    attempts = 0
    while attempts < 3000 and any(found[k] < wanted[k] for k in wanted):
        attempts += 1
        txs = ["TX_" + secrets.token_hex(5) for _ in range(rng.randint(4, 7))]
        resources = ["RES_" + secrets.token_hex(5) for _ in range(rng.randint(3, 6))]
        events = []
        owners = {}
        queued = defaultdict(set)
        for _ in range(rng.randint(10, 28)):
            if owners and rng.random() < 0.28:
                resource = rng.choice(list(owners.keys()))
                tx = owners[resource]
                events.append((tx, resource, "RELEASE"))
                # This tracking is only for generating valid RELEASE records.
                # Stop tracking this resource rather than predicting its FIFO owner;
                # future ACQUIRE records remain valid regardless.
                owners.pop(resource, None)
                queued.pop(resource, None)
            else:
                resource = rng.choice(resources)
                tx = rng.choice(txs)
                events.append((tx, resource, "ACQUIRE"))
                if resource not in owners:
                    owners[resource] = tx
                elif owners[resource] != tx:
                    queued[resource].add(tx)
        verdict, _ = oracle(events)
        if found[verdict] < wanted[verdict]:
            cases.append(events)
            found[verdict] += 1

    assert found == wanted, f"Could not generate balanced hidden cases: {found}"
    rng.shuffle(cases)
    return cases


def test_hidden_general_behavior(tmp_path):
    rebuilt = tmp_path / ("rebuilt_" + secrets.token_hex(6))
    compile_result = subprocess.run(
        ["g++", "-std=c++17", "-O2", SOURCE_PATH, "-o", str(rebuilt)],
        capture_output=True, text=True, timeout=30
    )
    assert compile_result.returncode == 0, compile_result.stderr

    binaries = [BINARY_PATH, str(rebuilt)]
    for index, events in enumerate(generated_cases()):
        expected_stdout, expected_code = oracle(events)
        case_dir = tmp_path / ("batch_" + secrets.token_hex(8))
        case_dir.mkdir()
        csv_path = case_dir / ("transactions_" + secrets.token_hex(8) + ".csv")
        with open(csv_path, "w", newline="") as f:
            f.write("tx_id,resource_id,action\n")
            for tx, resource, action in events:
                f.write(f"{tx},{resource},{action}\n")

        for binary in binaries:
            result = run_validator(binary, str(csv_path))
            assert result.returncode == expected_code, (
                f"Case {index}: expected exit {expected_code}, got {result.returncode}; "
                f"stdout={result.stdout!r}, stderr={result.stderr!r}"
            )
            assert result.stdout.strip() == expected_stdout, (
                f"Case {index}: expected {expected_stdout}, got {result.stdout!r}"
            )


def test_requires_csv_argument():
    result = subprocess.run([BINARY_PATH], capture_output=True, text=True, timeout=5)
    assert result.returncode != 0, "Validator must not report success without a CSV path argument."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
