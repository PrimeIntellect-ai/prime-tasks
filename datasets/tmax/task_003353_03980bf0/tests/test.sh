#!/bin/bash
set -u
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

ORACLE_HOLD="$(mktemp -d /root/cluster-oracle.XXXXXX)" || exit 0
ORACLE_HIDDEN="$ORACLE_HOLD/cluster_verifier"

cleanup() {
    if [ -e "$ORACLE_HIDDEN" ]; then
        mv "$ORACLE_HIDDEN" /app/cluster_verifier 2>/dev/null || true
        chmod 755 /app/cluster_verifier 2>/dev/null || true
    fi
    rmdir "$ORACLE_HOLD" 2>/dev/null || true
}
trap cleanup EXIT

if [ ! -x /app/cluster_verifier ]; then
    exit 0
fi
mv /app/cluster_verifier "$ORACLE_HIDDEN" || exit 0
chmod 700 "$ORACLE_HIDDEN" || exit 0
export TEST_ORACLE_PATH="$ORACLE_HIDDEN"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import grp
import json
import os
import pwd
import random
import stat
import subprocess
import tempfile

import pytest

ORACLE_PATH = os.environ["TEST_ORACLE_PATH"]
AGENT_SCRIPT = "/home/user/verify_clusters.py"
USER = pwd.getpwnam("user")


def generate_random_graph_csv(filepath, num_nodes, num_edges):
    node_ids = random.sample(range(1, 100001), num_nodes)
    with open(filepath, "w") as f:
        for _ in range(num_edges):
            u = random.choice(node_ids)
            v = random.choice(node_ids)
            f.write(f"{u},{v}\n")


def test_submission_artifact():
    assert os.path.exists(ORACLE_PATH), f"Oracle binary missing: {ORACLE_PATH}"
    assert os.path.exists(AGENT_SCRIPT), f"Agent script missing: {AGENT_SCRIPT}"
    assert os.path.isfile(AGENT_SCRIPT), "Agent script is not a regular file."
    assert not os.path.islink(AGENT_SCRIPT), "Agent script must not be a symlink."
    with open(ORACLE_PATH, "rb") as oracle, open(AGENT_SCRIPT, "rb") as agent:
        assert oracle.read() != agent.read(), "Submission is byte-identical to the reference artifact."


@pytest.mark.parametrize("iteration", range(100))
def test_fuzz_equivalence(iteration):
    assert os.path.exists(ORACLE_PATH), f"Oracle binary missing: {ORACLE_PATH}"
    assert os.path.exists(AGENT_SCRIPT), f"Agent script missing: {AGENT_SCRIPT}"

    random.seed(42 + iteration)
    num_nodes = random.randint(50, 5000)
    num_edges = random.randint(0, 20000)

    with tempfile.TemporaryDirectory() as tmpdir:
        os.chmod(tmpdir, 0o755)
        input_csv = os.path.join(tmpdir, "input.csv")
        oracle_dir = os.path.join(tmpdir, "oracle")
        agent_dir = os.path.join(tmpdir, "agent")
        os.mkdir(oracle_dir, 0o700)
        os.mkdir(agent_dir, 0o700)
        os.chown(agent_dir, USER.pw_uid, USER.pw_gid)

        oracle_out = os.path.join(oracle_dir, "oracle.json")
        agent_out = os.path.join(agent_dir, "agent.json")
        generate_random_graph_csv(input_csv, num_nodes, num_edges)
        os.chmod(input_csv, 0o644)

        oracle_proc = subprocess.run(
            [ORACLE_PATH, "--in", input_csv, "--out", oracle_out],
            capture_output=True,
            text=True,
        )
        assert oracle_proc.returncode == 0, (
            f"Oracle failed on iteration {iteration}. Stderr: {oracle_proc.stderr}"
        )
        assert os.path.exists(oracle_out), "Oracle output JSON missing."
        os.chmod(oracle_out, 0o600)

        agent_proc = subprocess.run(
            [
                "runuser", "-u", "user", "--",
                "env", "-i", "PATH=/usr/local/bin:/usr/bin:/bin", "HOME=/home/user",
                "python3", AGENT_SCRIPT, "--in", input_csv, "--out", agent_out,
            ],
            capture_output=True,
            text=True,
        )
        assert agent_proc.returncode == 0, (
            f"Agent script failed on iteration {iteration}. Stderr: {agent_proc.stderr}"
        )
        assert os.path.exists(agent_out), "Agent output JSON missing."
        assert stat.S_ISREG(os.lstat(agent_out).st_mode), "Agent output is not a regular file."
        assert not os.path.islink(agent_out), "Agent output must not be a symlink."

        with open(oracle_out, "r") as f:
            try:
                oracle_data = json.load(f)
            except json.JSONDecodeError:
                pytest.fail("Oracle output is not valid JSON.")

        with open(agent_out, "r") as f:
            try:
                agent_data = json.load(f)
            except json.JSONDecodeError:
                pytest.fail("Agent output is not valid JSON.")

        if oracle_data != agent_data:
            pytest.fail(
                f"Mismatch on iteration {iteration} ({num_nodes} nodes, {num_edges} edges).\n"
                f"Oracle keys: {len(oracle_data)}, Agent keys: {len(agent_data)}"
            )

        with open(oracle_out, "rb") as f:
            oracle_bytes = f.read()
        with open(agent_out, "rb") as f:
            agent_bytes = f.read()
        assert agent_bytes == oracle_bytes, (
            f"Output is not bit-exact on iteration {iteration} "
            f"({num_nodes} nodes, {num_edges} edges)."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    RESULT=1
else
    RESULT=0
fi

cleanup
trap - EXIT
echo "$RESULT" > /logs/verifier/reward.txt
