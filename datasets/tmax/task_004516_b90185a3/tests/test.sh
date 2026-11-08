#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import json
import os
import random
import string
import subprocess
import tempfile

ORACLE_PATH = "/app/oracle_processor"
AGENT_PATH = "/home/user/fixed_processor.py"
REPO_PROCESSOR = "/app/wal_processor/processor.py"


def generate_wal_file(path, num_lines, records):
    operations = ["INSERT", "UPDATE", "DELETE"]
    with open(path, "w") as f:
        for _ in range(num_lines):
            ts = random.uniform(1600000000.0, 1700000000.0)
            op = random.choice(operations)
            key = f"key_{random.randint(1, 100)}"
            val = "".join(random.choices(string.ascii_letters, k=8))
            f.write(f"{ts},{op},{key},{val}\n")
            records.append((ts, op, key, val))


def expected_output(records):
    state = {}
    for _, op, key, val in sorted(records, key=lambda event: event[0]):
        if op in ("INSERT", "UPDATE"):
            state[key] = val
        elif op == "DELETE":
            state.pop(key, None)
    return json.dumps(state, sort_keys=True) + "\n"


def load_repo_processor():
    spec = importlib.util.spec_from_file_location("submitted_wal_processor", REPO_PROCESSOR)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_repository_fix_and_fuzz_equivalence():
    assert os.path.isfile(AGENT_PATH), f"Agent program {AGENT_PATH} does not exist."
    assert not os.path.islink(AGENT_PATH), "The fixed program must be a standalone file."
    assert os.access(AGENT_PATH, os.X_OK), f"Agent program {AGENT_PATH} is not executable."
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle program {ORACLE_PATH} is not executable."
    assert os.path.isfile(REPO_PROCESSOR), "The vendored repository processor is missing."

    with open(AGENT_PATH, "rb") as agent_file, open(ORACLE_PATH, "rb") as oracle_file:
        assert agent_file.read() != oracle_file.read(), "The submission is byte-identical to the reference oracle."

    processor = load_repo_processor()

    # The regression was a shared mutable default. Separate calls must return
    # separate event collections with no events retained from earlier calls.
    first = processor.parse_wal_chunk(["1,INSERT,alpha,one\n"])
    second = processor.parse_wal_chunk(["2,INSERT,beta,two\n"])
    assert first == [(1.0, "INSERT", "alpha", "one")]
    assert second == [(2.0, "INSERT", "beta", "two")], \
        "parse_wal_chunk still retains shared state between calls"
    assert first is not second, "parse_wal_chunk still reuses a mutable result list"

    random.seed(42)

    for i in range(5):
        with tempfile.TemporaryDirectory() as tmpdir:
            records = []
            num_files = random.randint(10, 20)
            for j in range(num_files):
                file_path = os.path.join(tmpdir, f"wal_{j}.log")
                num_lines = random.randint(100, 500)
                generate_wal_file(file_path, num_lines, records)

            expected = expected_output(records)

            oracle_proc = subprocess.run(
                [ORACLE_PATH, tmpdir], capture_output=True, text=True, timeout=30
            )
            agent_proc = subprocess.run(
                ["python3", AGENT_PATH, tmpdir], capture_output=True, text=True, timeout=30
            )
            direct_proc = subprocess.run(
                [AGENT_PATH, tmpdir], capture_output=True, text=True, timeout=30
            )

            assert oracle_proc.returncode == agent_proc.returncode, \
                f"Return code mismatch on fuzz dir {i}: oracle={oracle_proc.returncode}, agent={agent_proc.returncode}"
            assert oracle_proc.stdout == agent_proc.stdout, \
                f"Stdout mismatch on fuzz dir {i}.\nOracle:\n{oracle_proc.stdout[:500]}\n\nAgent:\n{agent_proc.stdout[:500]}"

            assert oracle_proc.returncode == 0, f"Oracle failed on valid WAL input: {oracle_proc.stderr[:500]}"
            assert agent_proc.returncode == 0, f"Agent failed on valid WAL input: {agent_proc.stderr[:500]}"
            assert agent_proc.stdout == expected, \
                f"Agent output is not the recovered state on fuzz dir {i}"
            assert direct_proc.returncode == 0 and direct_proc.stdout == expected, \
                "The executable standalone entry point did not produce the expected state"

            # Exercise the implementation fixed in the vendored repository too.
            repo_state = processor.process_wal_dir(tmpdir)
            assert json.dumps(repo_state, sort_keys=True) + "\n" == expected, \
                f"The repository implementation remains incorrect on fuzz dir {i}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
