#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import os
import random
import shutil
import string
import subprocess
import tempfile
import pytest

ORACLE_PATH = "/app/log_oracle"
AGENT_PATH = "/home/user/solution"
SOURCE_PATH = "/home/user/solution.go"
N_TESTS = 200


def generate_csv_input(seed):
    random.seed(seed)
    num_rows = random.randint(10, 500)

    output = io.StringIO()
    writer = csv.writer(output, quoting=csv.QUOTE_MINIMAL)
    writer.writerow(["timestamp", "message", "metric"])

    seen_messages = []
    for _ in range(num_rows):
        timestamp = random.randint(1600000000, 1600000500)

        if seen_messages and random.random() < 0.20:
            message = random.choice(seen_messages)
        else:
            length = random.randint(5, 20)
            chars = string.ascii_letters + string.digits
            message = "".join(random.choice(chars) for _ in range(length))
            if random.random() < 0.10:
                insert_pos = random.randint(0, len(message))
                message = message[:insert_pos] + "\n" + message[insert_pos:]
            seen_messages.append(message)

        metric = random.randint(0, 100)
        writer.writerow([timestamp, message, metric])

    return output.getvalue().encode("utf-8")


def test_solution_exists():
    assert os.path.exists(AGENT_PATH), f"Agent solution binary missing at {AGENT_PATH}"
    assert os.path.isfile(AGENT_PATH), f"Agent solution path {AGENT_PATH} is not a file"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent solution binary at {AGENT_PATH} is not executable"
    with open(AGENT_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Agent solution is not a compiled ELF executable"

    assert os.path.exists(SOURCE_PATH), f"Go source missing at {SOURCE_PATH}"
    assert os.path.isfile(SOURCE_PATH), f"Go source path {SOURCE_PATH} is not a file"

    with open(AGENT_PATH, "rb") as agent_file, open(ORACLE_PATH, "rb") as oracle_file:
        assert agent_file.read() != oracle_file.read(), "Agent solution must not be a byte-identical copy of the oracle"


def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_PATH)
    assert os.path.exists(AGENT_PATH)

    cases = [generate_csv_input(seed=42 + i) for i in range(N_TESTS)]
    expected = []
    for csv_data in cases:
        oracle_proc = subprocess.run(
            [ORACLE_PATH],
            input=csv_data,
            capture_output=True,
            timeout=5,
        )
        expected.append((oracle_proc.stdout, oracle_proc.stderr))

    work = tempfile.mkdtemp(prefix="verifier-build-")
    try:
        source_copy = os.path.join(work, "solution.go")
        shutil.copyfile(SOURCE_PATH, source_copy)
        built_binary = os.path.join(work, "solution")
        cache_dir = os.path.join(work, "gocache")
        os.mkdir(cache_dir)
        env = os.environ.copy()
        env["CGO_ENABLED"] = "0"
        env["GOCACHE"] = cache_dir
        build_proc = subprocess.run(
            ["go", "build", "-trimpath", "-o", built_binary, source_copy],
            capture_output=True,
            timeout=60,
            env=env,
            cwd=work,
        )
        assert build_proc.returncode == 0, (
            "solution.go could not be independently compiled:\n"
            + build_proc.stderr.decode("utf-8", errors="replace")
        )

        jail = os.path.join(work, "jail")
        os.mkdir(jail, 0o755)
        jailed_binary = os.path.join(jail, "solution")
        shutil.copyfile(built_binary, jailed_binary)
        os.chmod(jailed_binary, 0o755)

        for i, csv_data in enumerate(cases):
            agent_proc = subprocess.run(
                ["chroot", "--userspec=65534:65534", jail, "/solution"],
                input=csv_data,
                capture_output=True,
                timeout=5,
            )
            oracle_out, oracle_err = expected[i]
            agent_out = agent_proc.stdout

            if oracle_out != agent_out:
                error_msg = (
                    f"Mismatch on test case {i+1}!\n\n"
                    f"--- INPUT CSV ---\n{csv_data.decode('utf-8')[:500]}...\n\n"
                    f"--- ORACLE STDOUT ---\n{oracle_out.decode('utf-8', errors='replace')}\n\n"
                    f"--- AGENT STDOUT ---\n{agent_out.decode('utf-8', errors='replace')}\n\n"
                    f"Oracle stderr: {oracle_err.decode('utf-8', errors='replace')}\n"
                    f"Agent stderr: {agent_proc.stderr.decode('utf-8', errors='replace')}\n"
                )
                pytest.fail(error_msg)
    finally:
        shutil.rmtree(work, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
