#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import subprocess
import sys
import tempfile
from decimal import Decimal, localcontext

RECOVERED_FILE = "/home/user/recovered_logs.txt"
AGGREGATOR = "/home/user/aggregator.py"
FINAL_SUM_FILE = "/home/user/final_sum.txt"
EXPECTED_SUM = "100000099.68"


def expected_recovered_bytes():
    lines = [json.dumps({"id": 0, "amount": "100000000.0"})]
    for i in range(1, 10001):
        if i % 500 == 0:
            lines.append('{"id": ' + str(i) + ', "amount": 0.01\x00')
        elif i % 700 == 0:
            lines.append('{"id": ' + str(i) + ', "amount": ')
        else:
            lines.append(json.dumps({"id": i, "amount": "0.01"}))
    return ("\n".join(lines) + "\n").encode("utf-8")


def run_aggregator(path):
    result = subprocess.run(
        [sys.executable, AGGREGATOR, path],
        cwd="/tmp",
        text=True,
        capture_output=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"aggregator.py failed with exit code {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    match = re.fullmatch(
        r"\s*Total:\s*([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)\s*",
        result.stdout,
    )
    assert match, f"Unexpected aggregator output: {result.stdout!r}"
    return Decimal(match.group(1))


def test_recovered_logs_exists_and_valid():
    assert os.path.exists(RECOVERED_FILE), f"Recovered log file {RECOVERED_FILE} does not exist."

    with open(RECOVERED_FILE, "r", encoding="utf-8", errors="replace") as f:
        lines = f.readlines()

    assert len(lines) == 10001, f"Expected 10001 lines in recovered logs, but found {len(lines)}."

    with open(RECOVERED_FILE, "rb") as f:
        recovered = f.read()
    assert recovered == expected_recovered_bytes(), (
        "recovered_logs.txt does not exactly match the deleted transactions.log contents"
    )


def test_aggregator_handles_corruption_and_exact_arithmetic():
    assert os.path.isfile(AGGREGATOR), f"Aggregation script {AGGREGATOR} does not exist."

    rng = random.SystemRandom()
    baseline = 10**24 + rng.randrange(10**10, 10**12)
    amounts = [str(baseline)]
    amounts.extend(["0.01"] * rng.randrange(1300, 1800))
    amounts.extend(["0.0000001"] * rng.randrange(250, 400))
    amounts.extend(["-2.50", "3.14159"])
    rng.shuffle(amounts)

    payload = [
        b'{"id": 1, "amount": 0.01\x00\n',
        b'{"id": 2, "amount": \n',
        b'not json at all\n',
    ]
    for index, amount in enumerate(amounts, 10):
        payload.append((json.dumps({"id": index, "amount": amount}) + "\n").encode("utf-8"))
        if index % 317 == 0:
            payload.append(b'{"truncated": true\n')

    with tempfile.NamedTemporaryFile(prefix="aggregate-check-", suffix=".log", delete=False) as f:
        challenge_path = f.name
        for part in payload:
            f.write(part)

    try:
        with localcontext() as context:
            context.prec = 80
            expected = sum((Decimal(value) for value in amounts), Decimal(0))
        actual = run_aggregator(challenge_path)
        assert actual == expected, f"Expected exact total {expected}, got {actual}"
    finally:
        os.unlink(challenge_path)


def test_aggregator_on_recovered_log():
    actual = run_aggregator(RECOVERED_FILE)
    assert actual == Decimal(EXPECTED_SUM), (
        f"aggregator.py produced {actual} for the recovered log; expected {EXPECTED_SUM}"
    )


def test_final_sum_correct():
    assert os.path.exists(FINAL_SUM_FILE), f"Final sum file {FINAL_SUM_FILE} does not exist."

    with open(FINAL_SUM_FILE, "r", encoding="utf-8") as f:
        content = f.read().strip()

    expected_sum = "100000099.68"
    assert content == expected_sum, f"Expected final sum to be exactly '{expected_sum}', but got '{content}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
