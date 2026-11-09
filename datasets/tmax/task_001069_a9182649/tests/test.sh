#!/bin/bash
set -u
mkdir -p /logs/verifier
reward=0
trap 'echo "$reward" > /logs/verifier/reward.txt' EXIT

ORACLE_PATH=/tests/graph_oracle
SUBMITTED_PATH=/home/user/graph_eval.py
SANDBOX_DIR=/var/lib/graph-verifier
SANDBOX_PATH=$SANDBOX_DIR/graph_eval.py

# Stop any processes left by the development user, then make the development
# oracle and the rest of the user's home inaccessible during evaluation.
pkill -9 -u "$(id -u user)" 2>/dev/null || true
rm -f /app/graph_oracle
chmod 700 /app 2>/dev/null || true

if [ ! -f "$ORACLE_PATH" ] || [ ! -f "$SUBMITTED_PATH" ] || [ -L "$SUBMITTED_PATH" ]; then
    exit 0
fi

chmod 700 "$ORACLE_PATH" || exit 0
rm -rf "$SANDBOX_DIR"
mkdir -p "$SANDBOX_DIR"
cp -- "$SUBMITTED_PATH" "$SANDBOX_PATH" || exit 0
chown -R root:root "$SANDBOX_DIR"
chmod 755 "$SANDBOX_DIR"
chmod 444 "$SANDBOX_PATH"
chmod 700 /home/user 2>/dev/null || true

cat << 'TEST_EOF' > /tmp/test_final_state.py
import filecmp
import os
import random
import string
import subprocess
import pytest

ORACLE_PATH = "/tests/graph_oracle"
SUBMITTED_PATH = "/home/user/graph_eval.py"
AGENT_PATH = "/var/lib/graph-verifier/graph_eval.py"
N_FUZZ = 1000


def random_string(min_len=1, max_len=10):
    length = random.randint(min_len, max_len)
    return ''.join(random.choice(string.ascii_letters + string.digits) for _ in range(length))


def generate_valid_dag(num_nodes, num_edges):
    nodes = [random_string() for _ in range(num_nodes)]
    nodes = list(set(nodes))
    num_nodes = len(nodes)

    lines = []
    for node in nodes:
        latency = random.randint(1, 10000)
        lines.append(f"V {node} {latency}")

    edges = set()
    if num_nodes > 1:
        for _ in range(num_edges):
            u_idx = random.randint(0, num_nodes - 2)
            v_idx = random.randint(u_idx + 1, num_nodes - 1)
            edges.add((nodes[u_idx], nodes[v_idx]))

    for u, v in edges:
        lines.append(f"E {u} {v}")

    random.shuffle(lines)
    return "\n".join(lines) + "\n"


def generate_cyclic_graph(num_nodes, num_edges):
    if num_nodes < 2:
        num_nodes = 2
    nodes = [random_string() for _ in range(num_nodes)]
    nodes = list(set(nodes))
    num_nodes = len(nodes)

    lines = []
    for node in nodes:
        latency = random.randint(1, 10000)
        lines.append(f"V {node} {latency}")

    cycle_len = random.randint(2, num_nodes)
    cycle_nodes = random.sample(nodes, cycle_len)
    for i in range(cycle_len):
        u = cycle_nodes[i]
        v = cycle_nodes[(i + 1) % cycle_len]
        lines.append(f"E {u} {v}")

    random.shuffle(lines)
    return "\n".join(lines) + "\n"


def generate_undeclared_nodes(num_nodes, num_edges):
    nodes = [random_string() for _ in range(num_nodes)]
    nodes = list(set(nodes))

    lines = []
    for node in nodes:
        latency = random.randint(1, 10000)
        lines.append(f"V {node} {latency}")

    undeclared = random_string(11, 15)
    if nodes:
        lines.append(f"E {nodes[0]} {undeclared}")
    else:
        lines.append(f"E {undeclared} {random_string(11, 15)}")

    random.shuffle(lines)
    return "\n".join(lines) + "\n"


def generate_malformed():
    choices = [
        "V missing_latency",
        "V NODE -5",
        "V NODE 0",
        "E NODE",
        "RANDOM GARBAGE",
        "V NODE 10\nE NODE",
    ]
    return random.choice(choices) + "\n"


def generate_input():
    r = random.random()
    num_nodes = random.randint(1, 50)
    num_edges = random.randint(0, 100)

    if r < 0.70:
        return generate_valid_dag(num_nodes, num_edges)
    if r < 0.80:
        return generate_cyclic_graph(num_nodes, num_edges)
    if r < 0.90:
        return generate_undeclared_nodes(num_nodes, num_edges)
    return generate_malformed()


def run_oracle(input_data):
    proc = subprocess.run(
        [ORACLE_PATH],
        input=input_data.encode("utf-8"),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    return proc.stdout.decode("utf-8")


def run_agent(input_data):
    proc = subprocess.run(
        [
            "setpriv",
            "--reuid=65534",
            "--regid=65534",
            "--clear-groups",
            "--no-new-privs",
            "python3",
            AGENT_PATH,
        ],
        input=input_data.encode("utf-8"),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
        cwd="/var/lib/graph-verifier",
        env={"PATH": "/usr/bin:/bin", "PYTHONDONTWRITEBYTECODE": "1"},
    )
    return proc.stdout.decode("utf-8")


def test_graph_eval_equivalence():
    assert os.path.exists(ORACLE_PATH), f"Oracle missing at {ORACLE_PATH}"
    assert os.path.exists(SUBMITTED_PATH), f"Agent script missing at {SUBMITTED_PATH}"
    assert os.path.isfile(SUBMITTED_PATH) and not os.path.islink(SUBMITTED_PATH)
    assert os.path.isfile(AGENT_PATH) and not os.path.islink(AGENT_PATH)
    assert not filecmp.cmp(AGENT_PATH, ORACLE_PATH, shallow=False), "Submission is the reference executable"

    random.seed(42)

    for i in range(N_FUZZ):
        input_data = generate_input()
        oracle_out = run_oracle(input_data)
        agent_out = run_agent(input_data)

        if oracle_out != agent_out:
            pytest.fail(
                f"Mismatch on fuzz iteration {i}.\n"
                f"Input:\n{input_data}\n"
                f"Oracle Output:\n{oracle_out}\n"
                f"Agent Output:\n{agent_out}\n"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    reward=1
fi
exit 0
