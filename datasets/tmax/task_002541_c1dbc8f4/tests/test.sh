#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import random
import stat
import string
import subprocess
import tempfile
import pytest

ORACLE_PATH = "/tests/oracle.py"
AGENT_PATH = "/home/user/detect.py"
DIGRAPH_PATH = "/app/networkx/networkx/classes/digraph.py"
NUM_TESTS = 500


def generate_random_string(length=5):
    return ''.join(random.choices(string.ascii_letters + string.digits, k=length))


def generate_random_csv(filepath):
    num_nodes = random.randint(10, 100)
    num_edges = random.randint(15, 300)

    nodes = [generate_random_string() for _ in range(num_nodes)]
    edges = set()

    for _ in range(num_edges):
        u = random.choice(nodes)
        v = random.choice(nodes)
        if u != v:
            edges.add((u, v))

    with open(filepath, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['tx', 'waiting_for'])
        for u, v in edges:
            writer.writerow([u, v])

    return nodes


def test_artifacts_exist_and_are_distinct():
    assert os.path.isfile(ORACLE_PATH), f"Oracle program missing at {ORACLE_PATH}"
    assert os.path.isfile(AGENT_PATH), f"Agent script missing at {AGENT_PATH}"
    assert stat.S_ISREG(os.stat(AGENT_PATH, follow_symlinks=False).st_mode), "Agent script must be a regular file"
    assert not os.path.islink(AGENT_PATH), "Agent script must not be a symlink"
    with open(ORACLE_PATH, 'rb') as f:
        oracle_bytes = f.read()
    with open(AGENT_PATH, 'rb') as f:
        agent_bytes = f.read()
    assert agent_bytes != oracle_bytes, "Agent script must not be a byte-identical copy of the reference implementation"


def test_vendored_digraph_is_repaired():
    assert os.path.isfile(DIGRAPH_PATH), f"Vendored digraph.py missing at {DIGRAPH_PATH}"
    with open(DIGRAPH_PATH, 'r', encoding='utf-8') as f:
        source = f.read()
    assert "self._succ[u_of_edge][u_of_edge] = datadict" not in source, "Directed edge perturbation is still present"

    code = r'''
import os
import sys
sys.path.insert(0, "/app/networkx")
import networkx as nx
assert os.path.realpath(nx.__file__).startswith("/app/networkx/networkx/")
g = nx.DiGraph()
g.add_edge("u", "v")
assert g.has_edge("u", "v")
assert not g.has_edge("u", "u")
assert list(g.successors("u")) == ["v"]
g.add_edges_from([("v", "w"), ("a", "b")])
assert g.has_edge("v", "w")
assert g.has_edge("a", "b")
assert nx.shortest_path(g, "u", "w") == ["u", "v", "w"]
'''
    proc = subprocess.run(["python3", "-S", "-c", code], capture_output=True, text=True)
    assert proc.returncode == 0, f"Vendored networkx directed-graph checks failed:\n{proc.stderr}"


def test_agent_imports_vendored_networkx():
    with tempfile.TemporaryDirectory() as tmpdir:
        csv_path = os.path.join(tmpdir, "graph.csv")
        with open(csv_path, 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['tx', 'waiting_for'])
            writer.writerows([
                ('T', 'B'),
                ('B', 'T'),
                ('T', 'A'),
                ('A', 'T'),
            ])

        proc = subprocess.run(
            ["python3", "-S", "-v", AGENT_PATH, csv_path, "T"],
            capture_output=True,
            text=True,
        )
        assert proc.returncode == 0, f"Agent failed using system Python without site-packages:\n{proc.stderr}"
        assert proc.stdout.strip() == "T,A,T"
        assert "/app/networkx/networkx/" in proc.stderr, "Agent did not import the vendored networkx package"


def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_PATH), f"Oracle program missing at {ORACLE_PATH}"
    assert os.path.isfile(AGENT_PATH), f"Agent script missing at {AGENT_PATH}"

    random.seed(42)

    with tempfile.TemporaryDirectory() as tmpdir:
        csv_path = os.path.join(tmpdir, "graph.csv")

        for i in range(NUM_TESTS):
            nodes = generate_random_csv(csv_path)

            # Pick a random target node, sometimes one that might not be in the graph
            target_tx_id = random.choice(nodes) if random.random() < 0.9 else generate_random_string()

            oracle_cmd = ["python3", ORACLE_PATH, csv_path, target_tx_id]
            # -S prevents fallback to an installed site-packages copy of networkx.
            agent_cmd = ["python3", "-S", AGENT_PATH, csv_path, target_tx_id]

            oracle_proc = subprocess.run(oracle_cmd, capture_output=True, text=True)
            agent_proc = subprocess.run(agent_cmd, capture_output=True, text=True)

            assert oracle_proc.returncode == 0, f"Oracle failed on test {i} with error:\n{oracle_proc.stderr}"
            assert agent_proc.returncode == 0, f"Agent failed on test {i} with error:\n{agent_proc.stderr}"

            oracle_out = oracle_proc.stdout.strip()
            agent_out = agent_proc.stdout.strip()

            if oracle_out != agent_out:
                with open(csv_path, 'r') as f:
                    csv_content = f.read()
                pytest.fail(
                    f"Mismatch on test {i}!\n"
                    f"Target TX ID: {target_tx_id}\n"
                    f"CSV Content:\n{csv_content}\n"
                    f"Oracle output: {oracle_out}\n"
                    f"Agent output: {agent_out}\n"
                    f"Agent stderr: {agent_proc.stderr}"
                )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
