#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess
from collections import defaultdict

import pytest

SOURCE = "/home/user/compliance_check.c"
EXECUTABLE = "/home/user/compliance_check"
TRANSACTIONS = "/home/user/transactions.txt"
OUTPUT = "/home/user/flagged_users.log"
ORIGINAL_EXPECTED = [
    "U2 2 5050",
    "U1 4 1300",
    "U3 4 1200",
]


def read_output():
    assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} is missing. Did you run the program?"
    with open(OUTPUT, "r") as f:
        return [line.strip() for line in f.readlines() if line.strip()]


def assert_output(expected):
    actual = read_output()
    assert len(actual) == len(expected), f"Expected {len(expected)} lines in {OUTPUT}, found {len(actual)}."
    for i, (got, want) in enumerate(zip(actual, expected)):
        assert got == want, f"Line {i + 1} mismatch. Expected '{want}', got '{got}'."


def oracle(lines):
    outgoing = defaultdict(list)
    receivers = defaultdict(set)
    for line in lines:
        txid, timestamp, sender, receiver, amount = line.split()
        outgoing[sender].append((int(timestamp), int(amount)))
        receivers[sender].add(receiver)

    results = []
    for sender, transactions in outgoing.items():
        if len(receivers[sender]) < 2:
            continue
        transactions.sort(key=lambda item: item[0])
        amounts = [amount for _, amount in transactions]
        if len(amounts) < 3:
            maximum = sum(amounts)
        else:
            maximum = max(sum(amounts[i:i + 3]) for i in range(len(amounts) - 2))
        results.append((sender, len(receivers[sender]), maximum))

    results.sort(key=lambda item: (-item[2], item[0]))
    return [f"{sender} {count} {maximum}" for sender, count, maximum in results[:3]]


def make_case():
    token = secrets.token_hex(4)
    rng = random.SystemRandom()
    lines = []
    txid = 1
    base_time = rng.randrange(1700000000, 1800000000)

    def add_sender(sender, amounts, receiver_count):
        nonlocal txid
        for i, amount in enumerate(amounts):
            receiver = f"R{token}_{i % receiver_count}"
            timestamp = base_time + i * rng.randrange(2, 20)
            lines.append(f"{txid} {timestamp} {sender} {receiver} {amount}")
            txid += 1

    # The first sender's best window is internal, requiring chronological sorting
    # after the input lines are shuffled.
    add_sender(f"S{token}_HIGH", [rng.randrange(500, 1500), rng.randrange(14500, 15500), rng.randrange(14500, 15500), rng.randrange(14500, 15500), rng.randrange(500, 1500)], 3)

    # Two qualifying senders deliberately tie, exercising SenderID tie-breaking.
    tie_total = rng.randrange(35000, 38000)
    split_a = rng.randrange(10000, tie_total - 10000)
    split_b = rng.randrange(10000, tie_total - 10000)
    add_sender(f"S{token}_TIE_A", [split_a, tie_total - split_a], 2)
    add_sender(f"S{token}_TIE_B", [split_b, tie_total - split_b], 2)

    # Additional qualifying senders must be aggregated but should rank lower.
    add_sender(f"S{token}_LOW1", [rng.randrange(3000, 7000) for _ in range(5)], 2)
    add_sender(f"S{token}_LOW2", [rng.randrange(2000, 6000) for _ in range(3)], 3)

    # A very large sender with only one distinct receiver must be filtered out.
    add_sender(f"S{token}_FILTERED", [99999, 99999, 99999, 99999], 1)

    rng.shuffle(lines)
    return lines


def run_program(lines):
    with open(TRANSACTIONS, "w") as f:
        f.write("\n".join(lines) + "\n")
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    subprocess.run([EXECUTABLE], cwd="/home/user", check=True, timeout=10)
    assert_output(oracle(lines))


def test_c_source_code_exists():
    """Test that the C source code file exists."""
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} is missing."


def test_executable_exists():
    """Test that the compiled executable exists."""
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} is missing. Did you compile the C code?"
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."


def test_flagged_users_log_exists():
    """Test that the output log file exists."""
    assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} is missing. Did you run the program?"


def test_flagged_users_log_contents():
    """Test that the output log file contains the correct original results."""
    assert_output(ORIGINAL_EXPECTED)


def test_source_compiles_and_program_computes_results():
    with open(TRANSACTIONS, "rb") as f:
        original_transactions = f.read()
    original_output = None
    if os.path.isfile(OUTPUT):
        with open(OUTPUT, "rb") as f:
            original_output = f.read()

    try:
        subprocess.run(["gcc", SOURCE, "-o", EXECUTABLE], check=True, timeout=20)
        assert os.path.isfile(EXECUTABLE)
        assert os.access(EXECUTABLE, os.X_OK)

        # Remove the pre-generated answer and require the freshly compiled program
        # to reproduce it from the original transaction log.
        if os.path.exists(OUTPUT):
            os.remove(OUTPUT)
        subprocess.run([EXECUTABLE], cwd="/home/user", check=True, timeout=10)
        assert_output(ORIGINAL_EXPECTED)

        # Exercise the implementation on unpredictable inputs whose answers are
        # independently calculated by this verifier.
        run_program(make_case())
        run_program(make_case())
    finally:
        with open(TRANSACTIONS, "wb") as f:
            f.write(original_transactions)
        if original_output is None:
            if os.path.exists(OUTPUT):
                os.remove(OUTPUT)
        else:
            with open(OUTPUT, "wb") as f:
                f.write(original_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
