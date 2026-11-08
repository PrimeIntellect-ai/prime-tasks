#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import hashlib
import os
import random
import string
import subprocess


def generate_fuzz_input():
    year = random.randint(1970, 2038)
    month = random.randint(1, 12)
    day = random.randint(1, 28)
    hour = random.randint(0, 23)
    minute = random.randint(0, 59)
    sec = random.randint(0, 59)

    cat = random.choice(["INFO", "WARN", "ERROR", "DEBUG", "TRACE"])

    msg_len = random.randint(10, 100)
    chars = string.ascii_letters + string.digits + " @_.-"
    msg = "".join(random.choices(chars, k=msg_len))

    return f"{year:04d}.{day:02d}.{month:02d}/{hour:02d}:{minute:02d}:{sec:02d}|{cat}|{msg}"


def expected_output(line):
    ts_part, cat, msg = line.split('|', 2)
    year = int(ts_part[0:4])
    day = int(ts_part[5:7])
    month = int(ts_part[8:10])
    hour = int(ts_part[11:13])
    minute = int(ts_part[14:16])
    sec = int(ts_part[17:19])

    dt = datetime.datetime(
        year, month, day, hour, minute, sec,
        tzinfo=datetime.timezone.utc,
    )
    epoch = int(dt.timestamp())
    bucket = epoch % 7

    tags = sorted(word for word in msg.split() if word.startswith('@'))
    tag_str = ",".join(tags) if tags else "NONE"
    return f"Bucket:{bucket} Epoch:{epoch} Tags:{tag_str} Category:{cat}"


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.digest()


def assert_no_oracle_copy(oracle_binary):
    oracle_hash = sha256_file(oracle_binary)
    for search_root in ("/home/user", "/tmp", "/var/tmp", "/dev/shm"):
        if not os.path.isdir(search_root):
            continue
        for root, dirs, files in os.walk(search_root):
            for name in files:
                path = os.path.join(root, name)
                try:
                    if os.path.isfile(path) and sha256_file(path) == oracle_hash:
                        raise AssertionError(
                            f"Submission contains a byte-identical copy of the legacy parser: {path}"
                        )
                except (OSError, PermissionError):
                    continue


def test_fuzz_equivalence():
    agent_script = "/home/user/run.sh"
    oracle_binary = "/app/legacy_parser"

    assert os.path.exists(agent_script), f"Agent script {agent_script} not found."
    assert os.path.isfile(agent_script), f"Agent script {agent_script} is not a regular file."
    assert os.access(agent_script, os.X_OK), f"Agent script {agent_script} is not executable."
    assert os.path.exists(oracle_binary), f"Oracle binary {oracle_binary} not found."

    assert_no_oracle_copy(oracle_binary)

    random.seed(42)
    num_tests = 1000
    inputs = [generate_fuzz_input() for _ in range(num_tests)]
    input_str = "\n".join(inputs) + "\n"
    expected_lines = [expected_output(line) for line in inputs]

    # Preserve the original oracle sanity check while independently deriving all
    # answers used to grade the submission.
    oracle_proc = subprocess.run(
        [oracle_binary],
        input=input_str,
        text=True,
        capture_output=True,
    )
    assert oracle_proc.returncode == 0, f"Oracle binary failed with error: {oracle_proc.stderr}"
    oracle_lines = oracle_proc.stdout.strip().split("\n")
    assert len(oracle_lines) == num_tests, (
        f"Oracle did not output {num_tests} lines. Got {len(oracle_lines)}."
    )
    assert oracle_lines == expected_lines, "Independent expected-value calculation disagrees with oracle."

    # The oracle was available for reverse engineering, but must not be available
    # when the replacement is exercised.
    os.unlink(oracle_binary)
    assert not os.path.exists(oracle_binary), "Failed to remove oracle before testing replacement."

    agent_proc = subprocess.run(
        [agent_script],
        input=input_str,
        text=True,
        capture_output=True,
    )
    assert agent_proc.returncode == 0, f"Agent script failed with error: {agent_proc.stderr}"
    agent_lines = agent_proc.stdout.strip().split("\n")

    assert len(agent_lines) == num_tests, (
        f"Agent did not output {num_tests} lines. Got {len(agent_lines)}."
    )

    for i, (inp, expected, agent_out) in enumerate(zip(inputs, expected_lines, agent_lines)):
        assert expected == agent_out, (
            f"Mismatch on input {i+1}/{num_tests}:\n"
            f"Input:    {inp}\n"
            f"Expected: {expected}\n"
            f"Agent:    {agent_out}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
