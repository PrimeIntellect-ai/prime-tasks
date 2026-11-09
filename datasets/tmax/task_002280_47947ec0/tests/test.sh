#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess
import tempfile
import pytest

SCRIPT_PATH = "/home/user/detector.sh"


def run_detector(path):
    return subprocess.run(
        ["/bin/bash", SCRIPT_PATH, path],
        capture_output=True,
        timeout=10,
    ).returncode


def test_detector_adversarial_corpus():
    assert os.path.exists(SCRIPT_PATH), f"Missing script: {SCRIPT_PATH}"

    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"

    assert os.path.exists(clean_dir), f"Missing clean corpus dir: {clean_dir}"
    assert os.path.exists(evil_dir), f"Missing evil corpus dir: {evil_dir}"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]

    assert len(clean_files) > 0, "Clean corpus is empty."
    assert len(evil_files) > 0, "Evil corpus is empty."

    clean_failures = []
    for cf in clean_files:
        if run_detector(cf) != 0:
            clean_failures.append(os.path.basename(cf))

    evil_failures = []
    for ef in evil_files:
        if run_detector(ef) == 0:
            evil_failures.append(os.path.basename(ef))

    error_messages = []
    if evil_failures:
        error_messages.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed: {', '.join(evil_failures)}")
    if clean_failures:
        error_messages.append(f"{len(clean_failures)} of {len(clean_files)} clean modified: {', '.join(clean_failures)}")

    if error_messages:
        pytest.fail(" | ".join(error_messages))


def write_encrypted_log(path, transactions, rng):
    records = []
    actions = {"A": "Start", "B": "Process", "C": "Commit"}
    # Interleave transactions while retaining the normal A -> B -> C service flow.
    for service_index, service in enumerate(("A", "B", "C")):
        service_records = []
        for tx, times in transactions:
            service_records.append(
                f"[Service{service}] {times[service_index]} {actions[service]} {tx}\n"
            )
        rng.shuffle(service_records)
        records.extend(service_records)

    plaintext = "".join(records).encode()
    with open(path, "wb") as fh:
        fh.write(bytes(byte ^ 0x42 for byte in plaintext))


def test_detector_on_hidden_generated_logs():
    assert os.path.exists(SCRIPT_PATH), f"Missing script: {SCRIPT_PATH}"
    rng = random.SystemRandom()
    cases = []

    # Build fresh mixed cases with opaque names, including equality and values whose
    # decimal string ordering differs from their numeric ordering.
    for anomalous in ([False] * 10 + [True] * 10):
        transactions = []
        count = rng.randint(2, 6)
        bad_index = rng.randrange(count) if anomalous else None

        for index in range(count):
            tx = "tx_" + secrets.token_hex(6)
            if not anomalous and index == 0:
                # Valid numerically, but not under lexicographic comparison.
                times = (9, 10, 100)
            else:
                a = rng.randint(1, 10**9)
                b = a + rng.randint(0, 5000)
                c = b + rng.randint(0, 5000)
                times = (a, b, c)

            if index == bad_index:
                if rng.choice((True, False)):
                    a = rng.randint(2, 10**9)
                    b = a - rng.randint(1, min(a, 5000))
                    c = b + rng.randint(0, 5000)
                else:
                    a = rng.randint(1, 10**9)
                    b = a + rng.randint(0, 5000)
                    c = b - rng.randint(1, min(b, 5000))
                times = (a, b, c)

            transactions.append((tx, times))

        expected_nonzero = any(
            b < a or c < b for _, (a, b, c) in transactions
        )
        assert expected_nonzero == anomalous
        cases.append((transactions, expected_nonzero))

    rng.shuffle(cases)
    with tempfile.TemporaryDirectory(prefix="detector_inputs_") as directory:
        failures = []
        for transactions, expected_nonzero in cases:
            path = os.path.join(directory, secrets.token_hex(12) + ".dat")
            write_encrypted_log(path, transactions, rng)
            rc = run_detector(path)
            if (rc != 0) != expected_nonzero:
                failures.append(os.path.basename(path))

        assert not failures, f"Detector misclassified {len(failures)} generated logs: {', '.join(failures)}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
