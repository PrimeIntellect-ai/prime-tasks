#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import stat
import subprocess

ORACLE_PATH = "/app/primer_oracle"
AGENT_SCRIPT = "/home/user/my_primer_oracle.sh"
N_TESTS = 100
CHARSET = "ACGT"
MIN_LEN = 10
MAX_LEN = 50
SEED = 42


def generate_random_sequences(n, min_len, max_len, charset, seed):
    random.seed(seed)
    return [
        "".join(random.choice(charset) for _ in range(random.randint(min_len, max_len)))
        for _ in range(n)
    ]


def run_command(cmd, arg):
    result = subprocess.run(
        [cmd, arg],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
        env={"PATH": "/usr/bin:/bin", "LC_ALL": "C"},
    )
    return result.stdout.strip(), result.returncode


def expected_score(seq):
    length = len(seq)
    gc = sum(ch in "GC" for ch in seq)
    p = gc / length
    t = 0.5
    for _ in range(10):
        e = math.exp(t)
        t = t - ((t * e - p) / (e * (t + 1.0)))
    return f"{t * length:.6f}"


def assert_no_private_elf_helpers():
    for root in ("/home/user", "/tmp", "/var/tmp", "/dev/shm"):
        if not os.path.isdir(root):
            continue
        for directory, _, files in os.walk(root):
            for name in files:
                path = os.path.join(directory, name)
                if path == AGENT_SCRIPT:
                    continue
                try:
                    with open(path, "rb") as handle:
                        magic = handle.read(4)
                except (OSError, PermissionError):
                    continue
                assert magic != b"\x7fELF", f"ELF helper is not allowed: {path}"


def test_final_state():
    assert os.path.exists(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"
    assert os.path.isfile(AGENT_SCRIPT), f"{AGENT_SCRIPT} is not a file"
    assert stat.S_ISREG(os.lstat(AGENT_SCRIPT).st_mode), f"{AGENT_SCRIPT} must be a regular file"
    assert os.access(AGENT_SCRIPT, os.X_OK), f"{AGENT_SCRIPT} is not executable"

    with open(AGENT_SCRIPT, "rb") as handle:
        first_line = handle.readline(256)
    assert first_line.startswith(b"#!"), "Agent artifact must be a shebang script"
    assert b"sh" in first_line.lower(), "Agent artifact must be a Bash/sh script"

    assert os.path.exists(ORACLE_PATH), f"Oracle missing at {ORACLE_PATH}"

    # Retain the original seeded oracle comparisons, but collect their answers
    # before removing the binary so the submitted script cannot delegate to it.
    random_sequences = generate_random_sequences(
        N_TESTS, MIN_LEN, MAX_LEN, CHARSET, SEED
    )
    oracle_results = {}
    for seq in random_sequences:
        oracle_out, oracle_rc = run_command(ORACLE_PATH, seq)
        assert oracle_rc == 0
        assert oracle_out == expected_score(seq), f"Reference/model disagreement for {seq}"
        oracle_results[seq] = (oracle_out, oracle_rc)

    os.unlink(ORACLE_PATH)
    assert not os.path.exists(ORACLE_PATH), "Oracle remained available during agent tests"
    assert_no_private_elf_helpers()

    for seq in random_sequences:
        expected_out, expected_rc = oracle_results[seq]
        agent_out, agent_rc = run_command(AGENT_SCRIPT, seq)
        assert agent_rc == expected_rc, (
            f"Return code mismatch for input '{seq}'. "
            f"Expected {expected_rc}, Agent returned {agent_rc}"
        )
        assert agent_out == expected_out, (
            f"Output mismatch for input '{seq}'. Expected '{expected_out}', "
            f"Agent output: '{agent_out}'"
        )

    # Exercise every possible length/GC-count pair, with answers derived from
    # the specified numerical model rather than supplied by the oracle.
    for length in range(MIN_LEN, MAX_LEN + 1):
        for gc in range(length + 1):
            seq = "G" * gc + "A" * (length - gc)
            expected_out = expected_score(seq)
            agent_out, agent_rc = run_command(AGENT_SCRIPT, seq)
            assert agent_rc == 0, f"Nonzero return code for input '{seq}'"
            assert agent_out == expected_out, (
                f"Output mismatch for length={length}, gc={gc}. "
                f"Expected '{expected_out}', Agent output: '{agent_out}'"
            )


if __name__ == "__main__":
    test_final_state()
TEST_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
