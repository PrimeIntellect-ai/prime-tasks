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
import time

import pytest

SCRIPT_PATH = "/home/user/investigate_leak.sh"


@pytest.fixture(scope="session", autouse=True)
def run_script():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."

    result = subprocess.run([SCRIPT_PATH], capture_output=True, text=True, timeout=20)
    assert result.returncode == 0, f"Script failed to execute successfully. Stderr:\n{result.stderr}"


def test_leaked_ids():
    path = "/home/user/leaked_ids.txt"
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected = ["102", "108"]
    assert lines == expected, f"Incorrect contents in {path}. Expected {expected}, got {lines}"


def test_leaked_features():
    path = "/home/user/leaked_features.csv"
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected = ["102,0.6,60", "108,0.4,40"]
    assert lines == expected, f"Incorrect contents in {path}. Expected {expected}, got {lines}"


def test_leak_predictions():
    path = "/home/user/leak_predictions.txt"
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected = ["Prediction for 102: 0.99", "Prediction for 108: 0.99"]
    assert lines == expected, f"Incorrect contents in {path}. Expected {expected}, got {lines}"


def test_benchmark_output():
    path = "/home/user/benchmark.txt"
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, "r") as f:
        content = f.read()

    assert "real " in content, f"'real' timing not found in {path}"
    assert "user " in content, f"'user' timing not found in {path}"
    assert "sys " in content, f"'sys' timing not found in {path}"


def test_recomputes_from_changed_inputs_and_runs_timed_inference():
    rng = random.SystemRandom()
    ids = rng.sample(range(20000, 90000), 9)
    leaked = sorted(ids[1:4])
    train_ids = [ids[6], leaked[2], ids[0], leaked[0], ids[7], leaked[1]]
    test_ids = [ids[8], leaked[1], ids[5], leaked[0], ids[4], leaked[2]]

    feat_a = {i: f"{rng.randrange(1001, 9999) / 1000:.3f}" for i in ids}
    feat_b = {i: str(rng.randrange(1000, 9999)) for i in ids}

    def write_csv(path, header, rows):
        with open(path, "w") as f:
            f.write(header + "\n")
            for row in rows:
                f.write(row + "\n")

    write_csv(
        "/home/user/data/train.csv",
        "id,label",
        [f"{i},{rng.randrange(2)}" for i in train_ids],
    )
    write_csv(
        "/home/user/data/test.csv",
        "id,label",
        [f"{i},{rng.randrange(2)}" for i in test_ids],
    )

    source_order_a = ids[:]
    source_order_b = ids[:]
    rng.shuffle(source_order_a)
    rng.shuffle(source_order_b)
    write_csv(
        "/home/user/data/source_A.csv",
        "id,featA",
        [f"{i},{feat_a[i]}" for i in source_order_a],
    )
    write_csv(
        "/home/user/data/source_B.csv",
        "id,featB",
        [f"{i},{feat_b[i]}" for i in source_order_b],
    )

    token = secrets.token_hex(12)
    salt = rng.randrange(1000, 100000)
    delay = rng.uniform(0.20, 0.80)
    invocation_log = f"/tmp/inference-invocation-{token}.json"
    inference_source = f'''import json
import os
import sys
import time

if len(sys.argv) != 2:
    sys.exit(31)
with open(sys.argv[1], "r") as f:
    ids = [line.strip() for line in f if line.strip()]
with open({invocation_log!r}, "w") as f:
    json.dump({{"argument": os.path.realpath(sys.argv[1]), "ids": ids}}, f)
print({("INFERENCE_STDERR_" + token)!r}, file=sys.stderr, flush=True)
time.sleep({delay!r})
for value in ids:
    print(f"dyn:{token}:{{value}}:{{(int(value) * 37 + {salt}) % 997}}")
'''
    with open("/home/user/inference_batch.py", "w") as f:
        f.write(inference_source)

    for path in (
        "/home/user/leaked_ids.txt",
        "/home/user/leaked_features.csv",
        "/home/user/leak_predictions.txt",
        "/home/user/benchmark.txt",
        invocation_log,
    ):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    started = time.monotonic()
    result = subprocess.run([SCRIPT_PATH], capture_output=True, text=True, timeout=20)
    elapsed = time.monotonic() - started
    assert result.returncode == 0, f"Script failed on changed inputs. Stderr:\n{result.stderr}"

    with open("/home/user/leaked_ids.txt") as f:
        actual_ids = [line.strip() for line in f if line.strip()]
    expected_ids = [str(i) for i in leaked]
    assert actual_ids == expected_ids

    with open("/home/user/leaked_features.csv") as f:
        actual_features = [line.strip() for line in f if line.strip()]
    expected_features = [f"{i},{feat_a[i]},{feat_b[i]}" for i in leaked]
    assert actual_features == expected_features

    assert os.path.isfile(invocation_log), "The supplied inference program was not executed"
    with open(invocation_log) as f:
        invocation = json.load(f)
    assert invocation == {
        "argument": "/home/user/leaked_ids.txt",
        "ids": expected_ids,
    }

    with open("/home/user/leak_predictions.txt") as f:
        predictions = [line.strip() for line in f if line.strip()]
    expected_predictions = [
        f"dyn:{token}:{i}:{(i * 37 + salt) % 997}" for i in leaked
    ]
    assert predictions == expected_predictions

    with open("/home/user/benchmark.txt") as f:
        benchmark = f.read()
    assert f"INFERENCE_STDERR_{token}" in benchmark, (
        "Inference stderr was not captured with the time output"
    )

    timings = {}
    for name in ("real", "user", "sys"):
        matches = re.findall(rf"(?m)^{name} ([0-9]+(?:\\.[0-9]+)?)$", benchmark)
        assert len(matches) == 1, f"Expected one valid '{name}' timing line, got {matches!r}"
        timings[name] = float(matches[0])

    assert abs(timings["real"] - delay) < 0.15, (
        f"Reported real time {timings['real']} does not match the randomized "
        f"inference duration {delay}"
    )
    assert timings["real"] <= elapsed + 0.05
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
