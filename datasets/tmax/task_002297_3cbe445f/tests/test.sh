#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import secrets
import subprocess
import pytest

RUST_FILE = "/home/user/evaluate.rs"
LOG_FILE = "/home/user/transitions.log"
JSON_FILE = "/home/user/summary.json"
BINARY = "/tmp/evaluate_submission"


@pytest.fixture(scope="session", autouse=True)
def restore_agent_files():
    with open(LOG_FILE, "rb") as f:
        original_log = f.read()
    original_summary = None
    if os.path.isfile(JSON_FILE):
        with open(JSON_FILE, "rb") as f:
            original_summary = f.read()
    yield
    with open(LOG_FILE, "wb") as f:
        f.write(original_log)
    if original_summary is None:
        if os.path.exists(JSON_FILE):
            os.remove(JSON_FILE)
    else:
        with open(JSON_FILE, "wb") as f:
            f.write(original_summary)


def test_evaluate_rs_exists():
    rust_file = "/home/user/evaluate.rs"
    assert os.path.exists(rust_file), f"The Rust source file {rust_file} is missing."
    assert os.path.isfile(rust_file), f"The path {rust_file} is not a file."


def test_summary_json_exists_and_correct():
    json_file = "/home/user/summary.json"
    assert os.path.exists(json_file), f"The output file {json_file} is missing. Did you run your Rust program?"
    assert os.path.isfile(json_file), f"The path {json_file} is not a file."

    with open(json_file, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {json_file} does not contain valid JSON.")

    assert "final_state" in data, "The JSON is missing the 'final_state' key."
    assert "score" in data, "The JSON is missing the 'score' key."

    assert data["final_state"] == "NODE_X", f"Expected final_state to be 'NODE_X', but got '{data['final_state']}'."
    assert data["score"] == 26, f"Expected score to be 26, but got {data['score']}."


def test_evaluate_rs_compiles():
    result = subprocess.run(
        ["rustc", RUST_FILE, "-o", BINARY],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"evaluate.rs did not compile with rustc:\n{result.stderr}"
    assert os.path.isfile(BINARY), "rustc did not produce an executable."


def reference_result(lines):
    current = "START"
    score = 0
    pattern = re.compile(r"^\[SEQ\] State: (\S+) Action: (\S+) Weight: (-?\d+) Next: (\S+)$")
    for line in lines:
        if not line.startswith("[SEQ]"):
            continue
        match = pattern.fullmatch(line)
        assert match is not None, f"Verifier generated an invalid transition: {line!r}"
        source, _action, weight, destination = match.groups()
        if source != current:
            break
        score += int(weight)
        current = destination
    return {"final_state": current, "score": score}


def run_case(lines):
    expected = reference_result(lines)
    with open(LOG_FILE, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    if os.path.exists(JSON_FILE):
        os.remove(JSON_FILE)

    result = subprocess.run(
        [BINARY],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"The compiled program failed on a generated log (exit {result.returncode}).\n"
        f"stderr:\n{result.stderr}"
    )
    assert os.path.isfile(JSON_FILE), "The program did not generate /home/user/summary.json."
    try:
        with open(JSON_FILE, "r", encoding="utf-8") as f:
            actual = json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f"The generated summary.json is not valid JSON: {exc}")

    assert "final_state" in actual, "The JSON is missing the 'final_state' key."
    assert "score" in actual, "The JSON is missing the 'score' key."
    assert actual["final_state"] == expected["final_state"], (
        f"Expected final_state {expected['final_state']!r}, got {actual['final_state']!r}."
    )
    assert actual["score"] == expected["score"], (
        f"Expected score {expected['score']}, got {actual['score']!r}."
    )


def test_parser_and_state_machine_on_generated_logs():
    rng = random.SystemRandom()
    tag = secrets.token_hex(6).upper()

    states = [f"S_{tag}_{i}" for i in range(6)]
    weights = [rng.randint(2, 40), -rng.randint(1, 30), rng.randint(1, 50), -rng.randint(1, 20), rng.randint(1, 35), rng.randint(1, 25)]
    continuous = ["unrelated startup information"]
    current = "START"
    for i, (next_state, weight) in enumerate(zip(states, weights)):
        continuous.append(f"[SEQ] State: {current} Action: ACT_{i} Weight: {weight} Next: {next_state}")
        if i == 1:
            continuous.append(" [SEQ] State: SHOULD_NOT_PARSE Action: X Weight: 999 Next: WRONG")
        if i == 3:
            continuous.append("[DEBUG] generated diagnostic line")
        current = next_state
    run_case(continuous)

    first = f"FIRST_{tag}"
    second = f"SECOND_{tag}"
    discontinuous = [
        "noise before transitions",
        f"[SEQ] State: START Action: OPEN Weight: {-rng.randint(1, 20)} Next: {first}",
        f"[SEQ] State: {first} Action: STEP Weight: {rng.randint(1, 30)} Next: {second}",
        f"[SEQ] State: WRONG_{tag} Action: BREAK Weight: 500 Next: BAD_{tag}",
        f"[SEQ] State: {second} Action: MUST_NOT_RUN Weight: 777 Next: AFTER_{tag}",
    ]
    run_case(discontinuous)

    ignored_prefix = [
        f"prefix [SEQ] State: START Action: FAKE Weight: 900 Next: WRONG_{tag}",
        f"[SEQ] State: START Action: REAL Weight: {-rng.randint(2, 40)} Next: END_{tag}",
        f"[INFO] [SEQ] State: END_{tag} Action: FAKE Weight: 800 Next: WRONG2_{tag}",
    ]
    run_case(ignored_prefix)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
