#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import shutil
import subprocess
import string
import tempfile
import pytest

ORACLE_PATH = "/app/sql_generator"
AGENT_PATH = "/home/user/generate_sql"
SOURCE_PATH = "/home/user/generate_sql.go"


def generate_random_input():
    # Path lengths: 2 to 6 nodes
    path_len = random.randint(2, 6)
    aliases = list(string.ascii_uppercase[:path_len])
    path_str = "->".join(f"({a})" for a in aliases)

    # Nodes: 1 to 10 random integers between 1 and 999
    num_nodes = random.randint(1, 10)
    nodes = [str(random.randint(1, 999)) for _ in range(num_nodes)]
    nodes_str = ",".join(nodes)

    return f"GRAPH_UPDATE path={path_str} nodes={nodes_str}"


@pytest.fixture(scope="session")
def isolated_agent():
    assert os.path.isfile(SOURCE_PATH), f"Go source missing: {SOURCE_PATH}"

    sandbox = tempfile.mkdtemp(prefix="generate_sql_root_")
    rebuilt = os.path.join(sandbox, "generate_sql")
    try:
        build = subprocess.run(
            ["go", "build", "-o", rebuilt, SOURCE_PATH],
            capture_output=True,
            text=True,
            timeout=60,
        )
        assert build.returncode == 0, (
            f"Failed to compile {SOURCE_PATH}:\n{build.stdout}{build.stderr}"
        )
        assert os.path.isfile(rebuilt)
        assert os.access(rebuilt, os.X_OK)

        # A submitted copy of the shipped reference executable is not a Go rewrite.
        with open(rebuilt, "rb") as f:
            rebuilt_bytes = f.read()
        with open(ORACLE_PATH, "rb") as f:
            oracle_bytes = f.read()
        assert rebuilt_bytes != oracle_bytes, "Submission is byte-identical to the oracle"

        os.chmod(sandbox, 0o755)
        os.chmod(rebuilt, 0o755)
        yield sandbox
    finally:
        shutil.rmtree(sandbox, ignore_errors=True)


def test_binaries_exist():
    assert os.path.isfile(ORACLE_PATH), f"Oracle binary missing: {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle binary not executable: {ORACLE_PATH}"
    assert os.path.isfile(AGENT_PATH), f"Agent binary missing: {AGENT_PATH}. Did you compile it?"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent binary not executable: {AGENT_PATH}"


def test_fuzz_equivalence(isolated_agent):
    random.seed(42)

    for i in range(100):
        test_input = generate_random_input()

        try:
            oracle_proc = subprocess.run(
                [ORACLE_PATH, test_input],
                capture_output=True,
                text=True,
                check=True,
                timeout=5,
            )
            oracle_output = oracle_proc.stdout
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle failed on input: {test_input}\nError: {e.stderr}")
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle timed out on input: {test_input}")

        # Run the executable rebuilt from the submitted Go source in a minimal
        # filesystem containing no /app/sql_generator or other submitted files.
        try:
            agent_proc = subprocess.run(
                ["chroot", "--userspec=65534:65534", isolated_agent,
                 "/generate_sql", test_input],
                capture_output=True,
                text=True,
                check=True,
                timeout=5,
            )
            agent_output = agent_proc.stdout
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Agent program failed on input: {test_input}\nError: {e.stderr}")
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent program timed out on input: {test_input}")

        assert agent_output == oracle_output, (
            f"Mismatch on iteration {i+1}!\n"
            f"Input: {test_input}\n"
            f"Expected (Oracle):\n{oracle_output}\n"
            f"Got (Agent):\n{agent_output}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
