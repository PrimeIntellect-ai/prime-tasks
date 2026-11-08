#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import random
import subprocess
import tempfile
import pytest


def get_agent_cmd(edges_path, features_path):
    if os.path.exists("/home/user/my_propagate.py"):
        return ["python3", "/home/user/my_propagate.py", edges_path, features_path]
    elif os.path.exists("/home/user/my_propagate"):
        return ["/home/user/my_propagate", edges_path, features_path]
    elif os.path.exists("/home/user/my_propagate.sh"):
        return ["bash", "/home/user/my_propagate.sh", edges_path, features_path]
    pytest.fail("Agent entry point not found. Expected /home/user/my_propagate.py or equivalent executable.")


def file_hash(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.digest()


def test_fuzz_equivalence():
    oracle_cmd = "/app/gcn_propagate"
    assert os.path.exists(oracle_cmd), "Oracle binary /app/gcn_propagate is missing."

    oracle_hash = file_hash(oracle_cmd)
    for root, _, files in os.walk("/home/user"):
        for name in files:
            path = os.path.join(root, name)
            try:
                if os.path.isfile(path) and file_hash(path) == oracle_hash:
                    pytest.fail(f"Submission contains a byte-identical copy of the oracle: {path}")
            except (OSError, PermissionError):
                continue

    random.seed(42)

    with tempfile.TemporaryDirectory() as tmpdir:
        cases = []
        for i in range(50):
            V = random.randint(10, 100)
            p = random.uniform(0.05, 0.3)

            edges = []
            for u in range(V):
                for v in range(u + 1, V):
                    if random.random() < p:
                        edges.append((u, v))

            features = {u: random.uniform(-10.0, 10.0) for u in range(V)}
            case_dir = os.path.join(tmpdir, str(i))
            os.mkdir(case_dir)
            edges_path = os.path.join(case_dir, "edges.csv")
            features_path = os.path.join(case_dir, "features.csv")

            with open(edges_path, "w") as f:
                f.write("source,target\n")
                for u, v in edges:
                    f.write(f"{u},{v}\n")

            with open(features_path, "w") as f:
                f.write("node_id,feature\n")
                for u, feat in features.items():
                    f.write(f"{u},{feat}\n")

            oracle_res = subprocess.run(
                [oracle_cmd, edges_path, features_path],
                capture_output=True,
                text=True,
            )
            assert oracle_res.returncode == 0, (
                f"Oracle program failed on iteration {i} with stderr:\n{oracle_res.stderr}"
            )
            cases.append((i, V, p, edges_path, features_path, oracle_res.stdout))

        # The agent was allowed to inspect the legacy tool while solving the task,
        # but it must not be able to delegate execution to that tool during grading.
        os.unlink(oracle_cmd)

        for i, V, p, edges_path, features_path, expected_stdout in cases:
            agent_cmd = get_agent_cmd(edges_path, features_path)
            agent_res = subprocess.run(agent_cmd, capture_output=True, text=True)

            assert agent_res.returncode == 0, (
                f"Agent program failed on iteration {i} with stderr:\n{agent_res.stderr}"
            )

            if agent_res.stdout != expected_stdout:
                pytest.fail(
                    f"Output mismatch on fuzz iteration {i}.\n"
                    f"Graph parameters: V={V}, p={p:.3f}\n\n"
                    f"--- Oracle Output ---\n{expected_stdout}\n"
                    f"--- Agent Output ---\n{agent_res.stdout}\n"
                )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
