#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import random
import csv
import string
import pytest


def test_translations_db_exists():
    path = "/home/user/translations.db"
    assert os.path.isfile(path), f"Database file {path} is missing. Did you create it?"


def test_agent_process_exists():
    path = "/home/user/process"
    assert os.path.isfile(path), f"Executable {path} does not exist. Did you compile your Go program?"
    assert os.access(path, os.X_OK), f"File {path} is not executable."


def test_fuzz_equivalence():
    oracle_path = "/tests/oracle_process"
    agent_path = "/home/user/process"

    assert os.path.isfile(oracle_path), f"Oracle {oracle_path} missing."

    with open(oracle_path, "rb") as f:
        oracle_bytes = f.read()
    with open(agent_path, "rb") as f:
        agent_bytes = f.read()
    assert agent_bytes != oracle_bytes, "Agent executable must not be a byte-identical copy of the reference implementation."

    terms = []
    csv_path = "/home/user/terms.csv"
    if os.path.isfile(csv_path):
        with open(csv_path, "r", encoding="utf-8") as f:
            reader = csv.reader(f)
            for row in reader:
                if row:
                    terms.append(row[0])

    if not terms:
        terms = ["cat", "dog", "hello", "world"]

    random.seed(42)

    def generate_random_string():
        length = random.randint(10, 500)
        vocab = terms + ["SECRET"] * 5 + ["apple", "banana"]
        punctuations = list(string.punctuation) + [" ", "\t", "\n"]
        emojis = ["😀", "🚀", "🌟", "🔥", "ñ", "é", "汉", "字"]

        parts = []
        current_len = 0
        while current_len < length:
            choice = random.choice(["word", "punct", "emoji", "random_char"])
            if choice == "word":
                w = random.choice(vocab)
                parts.append(w)
                current_len += len(w)
            elif choice == "punct":
                p = random.choice(punctuations)
                parts.append(p)
                current_len += len(p)
            elif choice == "emoji":
                e = random.choice(emojis)
                parts.append(e)
                current_len += len(e)
            else:
                c = random.choice(string.ascii_letters)
                parts.append(c)
                current_len += 1

        return "".join(parts)[:length]

    cases = []
    for _ in range(1000):
        input_str = generate_random_string()
        input_bytes = input_str.encode("utf-8")
        try:
            oracle_res = subprocess.run(
                [oracle_path], input=input_bytes, capture_output=True,
                check=True, timeout=2
            )
        except subprocess.TimeoutExpired:
            continue
        except subprocess.CalledProcessError:
            continue
        cases.append((input_str, input_bytes, oracle_res.stdout))

    # The oracle is uploaded only for verification and is removed before any
    # submitted executable is run, preventing delegation to it.
    os.remove(oracle_path)

    for input_str, input_bytes, oracle_out in cases:
        try:
            agent_res = subprocess.run(
                [agent_path], input=input_bytes, capture_output=True,
                check=True, timeout=2
            )
            agent_out = agent_res.stdout
        except subprocess.CalledProcessError as e:
            pytest.fail(
                f"Agent process failed on input: {repr(input_str)}\n"
                f"Error: {e.stderr.decode('utf-8', errors='replace')}"
            )
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent process timed out on input: {repr(input_str)}")

        if agent_out != oracle_out:
            expected_str = oracle_out.decode("utf-8", errors="replace")
            actual_str = agent_out.decode("utf-8", errors="replace")
            pytest.fail(
                f"Mismatch on input: {repr(input_str)}\n\n"
                f"Expected:\n{repr(expected_str)}\n\n"
                f"Got:\n{repr(actual_str)}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
