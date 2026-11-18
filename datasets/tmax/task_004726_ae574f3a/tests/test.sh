#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import resource
import subprocess
import time

AGENT_PATH = "/home/user/fast_primer.py"
ORACLE_PATH = "/app/oracle_primer"


def test_fast_primer_exists_and_executable():
    assert os.path.exists(AGENT_PATH), f"Agent script {AGENT_PATH} is missing."
    assert os.path.isfile(AGENT_PATH), f"{AGENT_PATH} is not a file."
    assert os.access(AGENT_PATH, os.X_OK), f"Agent script {AGENT_PATH} is not executable."


def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_PATH), f"Oracle {ORACLE_PATH} missing."
    assert os.path.isfile(ORACLE_PATH), f"Oracle {ORACLE_PATH} is not a file."

    with open(ORACLE_PATH, "rb") as f:
        oracle_bytes = f.read()
    with open(AGENT_PATH, "rb") as f:
        agent_bytes = f.read()
    assert agent_bytes != oracle_bytes, "Agent submission is byte-identical to the reference implementation."

    random.seed(42)
    bases = ['A', 'C', 'G', 'T']
    num_tests = 1000
    sequences = [
        "".join(random.choices(bases, k=random.randint(20, 100)))
        for _ in range(num_tests)
    ]

    expected = []
    oracle_cpu_start = resource.getrusage(resource.RUSAGE_CHILDREN)
    oracle_wall_start = time.perf_counter()
    for dna_seq in sequences:
        proc = subprocess.run(
            [ORACLE_PATH, dna_seq], capture_output=True, text=True, timeout=10
        )
        expected.append((proc.returncode, proc.stdout.strip()))
    oracle_wall = time.perf_counter() - oracle_wall_start
    oracle_cpu_end = resource.getrusage(resource.RUSAGE_CHILDREN)
    oracle_cpu = (
        oracle_cpu_end.ru_utime + oracle_cpu_end.ru_stime
        - oracle_cpu_start.ru_utime - oracle_cpu_start.ru_stime
    )

    # The reference was available while the agent worked, as promised, but it must
    # not remain callable when the submitted implementation is exercised.
    os.unlink(ORACLE_PATH)

    agent_cpu_start = resource.getrusage(resource.RUSAGE_CHILDREN)
    agent_wall_start = time.perf_counter()
    for dna_seq, (expected_code, expected_out) in zip(sequences, expected):
        proc = subprocess.run(
            [AGENT_PATH, dna_seq], capture_output=True, text=True, timeout=10
        )
        assert proc.returncode == expected_code, (
            f"Return code mismatch on input {dna_seq}. "
            f"Expected {expected_code}, got {proc.returncode}."
        )
        actual_out = proc.stdout.strip()
        assert actual_out == expected_out, (
            f"Output mismatch on input {dna_seq}.\n"
            f"Oracle output:\n{expected_out}\n\nAgent output:\n{actual_out}"
        )
    agent_wall = time.perf_counter() - agent_wall_start
    agent_cpu_end = resource.getrusage(resource.RUSAGE_CHILDREN)
    agent_cpu = (
        agent_cpu_end.ru_utime + agent_cpu_end.ru_stime
        - agent_cpu_start.ru_utime - agent_cpu_start.ru_stime
    )

    # A wrapper or exec-based copy of the deliberately slow oracle takes at least
    # the oracle's own CPU time. Require the requested optimized implementation to
    # provide a modest, aggregate speedup over 1000 runs.
    assert agent_cpu < oracle_cpu * 0.97, (
        f"Implementation is not faster than the deliberately slow oracle: "
        f"agent CPU {agent_cpu:.3f}s, oracle CPU {oracle_cpu:.3f}s "
        f"(wall times {agent_wall:.3f}s and {oracle_wall:.3f}s)."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
