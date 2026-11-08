#!/bin/bash
set -uo pipefail
mkdir -p /logs/verifier

ORACLE_PATH=/app/graph_oracle
AGENT_PATH=/home/user/graph_tool/target/release/graph_tool
PROJECT_PATH=/home/user/graph_tool
HOLD_DIR=""

cleanup() {
    if [ -n "${HOLD_DIR:-}" ] && [ -f "$HOLD_DIR/graph_oracle" ]; then
        mv "$HOLD_DIR/graph_oracle" "$ORACLE_PATH" || true
        rmdir "$HOLD_DIR" 2>/dev/null || true
    fi
}
trap cleanup EXIT

run_checks() {
    cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import random
import string
import subprocess
import tempfile
import pytest

ORACLE_PATH = "/app/graph_oracle"
AGENT_PATH = "/home/user/graph_tool/target/release/graph_tool"
PROJECT_PATH = "/home/user/graph_tool"
NUM_ITERATIONS = 50
EDGE_TYPES = ["KNOWS", "LIKES", "FOLLOWS", "BLOCKS", "TRUSTS"]


def generate_random_string(length):
    return ''.join(random.choices(string.ascii_letters + string.digits, k=length))


def run_program(executable, nodes_file, edges_file, stdin_data):
    try:
        result = subprocess.run(
            [executable, nodes_file, edges_file],
            input=stdin_data,
            text=True,
            capture_output=True,
            timeout=10
        )
        return result.returncode, result.stdout, result.stderr
    except subprocess.TimeoutExpired:
        return -1, "", "Timeout"


def file_hash(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.digest()


def test_rust_project_and_no_oracle_copy():
    cargo_toml = os.path.join(PROJECT_PATH, "Cargo.toml")
    source_dir = os.path.join(PROJECT_PATH, "src")
    main_rs = os.path.join(source_dir, "main.rs")
    assert os.path.isfile(cargo_toml), "Cargo.toml is missing"
    assert os.path.isfile(main_rs), "src/main.rs is missing"
    assert not os.path.exists(os.path.join(PROJECT_PATH, "build.rs")), "Custom build scripts are not allowed"
    assert not os.path.exists(os.path.join(PROJECT_PATH, ".cargo", "config")), "Cargo compiler overrides are not allowed"
    assert not os.path.exists(os.path.join(PROJECT_PATH, ".cargo", "config.toml")), "Cargo compiler overrides are not allowed"

    rust_sources = []
    for root, dirs, files in os.walk(source_dir):
        dirs[:] = [d for d in dirs if d != "target"]
        for name in files:
            if name.endswith(".rs"):
                rust_sources.append(os.path.join(root, name))
    assert rust_sources, "No Rust source files found"

    forbidden = [
        "std::process", "process::Command", "Command::new", "include_bytes!",
        "include_str!", "libc::exec", "libc::system"
    ]
    for path in rust_sources:
        text = open(path, "r", encoding="utf-8", errors="replace").read()
        for token in forbidden:
            assert token not in text, f"Rust source delegates to or embeds another executable ({token})"

    assert os.path.isfile(AGENT_PATH), f"Agent binary not found at {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent binary is not executable: {AGENT_PATH}"
    oracle_hash = file_hash(ORACLE_PATH)
    assert file_hash(AGENT_PATH) != oracle_hash, "Agent executable is a copy of the proprietary oracle"
    for root, _, files in os.walk(PROJECT_PATH):
        if os.path.abspath(root).startswith(os.path.join(PROJECT_PATH, "target")):
            continue
        for name in files:
            path = os.path.join(root, name)
            try:
                if os.path.isfile(path) and file_hash(path) == oracle_hash:
                    pytest.fail(f"Oracle binary copied into project: {path}")
            except OSError:
                pass


@pytest.mark.parametrize("iteration", range(NUM_ITERATIONS))
def test_fuzz_equivalence(iteration):
    assert os.path.isfile(AGENT_PATH), f"Agent binary not found at {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent binary is not executable: {AGENT_PATH}"

    random.seed(42 + iteration)
    num_nodes = random.randint(100, 1000)
    num_edges = random.randint(500, 5000)

    nodes = []
    for _ in range(num_nodes):
        node_id = generate_random_string(random.randint(4, 8))
        weight = random.randint(-100, 1000)
        nodes.append((node_id, weight))

    node_dict = {n[0]: n[1] for n in nodes}
    node_ids = list(node_dict.keys())

    edges = []
    for _ in range(num_edges):
        src = random.choice(node_ids)
        dst = random.choice(node_ids)
        etype = random.choice(EDGE_TYPES)
        edges.append((src, dst, etype))

    queries = []
    for _ in range(100):
        if random.random() < 0.05:
            start_node = generate_random_string(10)
        else:
            start_node = random.choice(node_ids)
        num_steps = random.randint(0, 5)
        query_parts = [start_node] + [random.choice(EDGE_TYPES) for _ in range(num_steps)]
        queries.append(",".join(query_parts))

    stdin_data = "\n".join(queries) + "\n"

    with tempfile.TemporaryDirectory() as tmpdir:
        nodes_file = os.path.join(tmpdir, "nodes.csv")
        edges_file = os.path.join(tmpdir, "edges.csv")
        with open(nodes_file, "w") as f:
            for node_id, weight in node_dict.items():
                f.write(f"{node_id},{weight}\n")
        with open(edges_file, "w") as f:
            for src, dst, etype in edges:
                f.write(f"{src},{dst},{etype}\n")

        oracle_code, oracle_out, oracle_err = run_program(ORACLE_PATH, nodes_file, edges_file, stdin_data)
        agent_code, agent_out, agent_err = run_program(AGENT_PATH, nodes_file, edges_file, stdin_data)

        assert agent_code == oracle_code, (
            f"Exit code mismatch on iteration {iteration}.\n"
            f"Oracle: {oracle_code}, Agent: {agent_code}\n"
            f"Agent stderr: {agent_err}"
        )
        if oracle_out != agent_out:
            display_oracle = oracle_out[:1000] + ("..." if len(oracle_out) > 1000 else "")
            display_agent = agent_out[:1000] + ("..." if len(agent_out) > 1000 else "")
            pytest.fail(
                f"Stdout mismatch on iteration {iteration}.\n"
                f"--- Oracle Output ---\n{display_oracle}\n"
                f"--- Agent Output ---\n{display_agent}\n"
            )
TEST_EOF

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short || return 1

    HOLD_DIR=$(mktemp -d /root/graph-verifier-oracle.XXXXXX) || return 1
    chmod 700 "$HOLD_DIR" || return 1
    mv "$ORACLE_PATH" "$HOLD_DIR/graph_oracle" || return 1

    rm -rf "$PROJECT_PATH/target" || return 1
    cargo build --release --manifest-path "$PROJECT_PATH/Cargo.toml" || return 1
    [ -f "$AGENT_PATH" ] && [ -x "$AGENT_PATH" ] || return 1
    python3 - "$AGENT_PATH" << 'INDEPENDENT_EOF' || return 1
import os
import pwd
import random
import string
import subprocess
import tempfile
import sys

agent = sys.argv[1]
edge_types = ["KNOWS", "LIKES", "FOLLOWS", "BLOCKS", "TRUSTS", "", "ODD"]
account = pwd.getpwnam("user")

with open(agent, "rb") as f:
    assert f.read(4) == b"\x7fELF", "rebuilt artifact is not an ELF executable"


def demote():
    os.setgroups([])
    os.setgid(account.pw_gid)
    os.setuid(account.pw_uid)


def expected(nodes, edges, stdin_data):
    weights = {}
    for line in nodes.splitlines():
        parts = line.split(",")
        if len(parts) >= 2:
            value = parts[1]
            if value and (value.isdigit() or (value[0] in "+-" and value[1:].isdigit())):
                try:
                    parsed = int(value)
                    if -(2**63) <= parsed <= 2**63 - 1:
                        weights[parts[0]] = parsed
                except ValueError:
                    pass
    adjacency = {}
    for line in edges.splitlines():
        parts = line.split(",")
        if len(parts) >= 3:
            adjacency.setdefault(parts[0], []).append((parts[2], parts[1]))
    output = []
    for raw in stdin_data.splitlines():
        query = raw.strip()
        if not query:
            continue
        parts = query.split(",")
        current = {parts[0]}
        for edge_type in parts[1:]:
            following = set()
            for node in current:
                for found_type, target in adjacency.get(node, []):
                    if found_type == edge_type:
                        following.add(target)
            current = following
        output.append("RESULT: " + str(sum(weights[n] for n in current if n in weights)))
    return "".join(line + "\n" for line in output)


for iteration in range(20):
    rng = random.Random(9000 + iteration)
    ids = [f"n{iteration}_{i}" for i in range(rng.randint(40, 180))]
    node_lines = [f"{node},{rng.randint(-5000, 5000)}" for node in ids]
    if iteration % 3 == 0:
        node_lines += [f"{ids[0]},17", "bad,not-a-number", "short"]
    edge_lines = []
    for _ in range(rng.randint(300, 1400)):
        edge_lines.append(f"{rng.choice(ids)},{rng.choice(ids)},{rng.choice(edge_types)}")
    edge_lines += [f"{ids[0]},missing,ODD", "malformed"]

    queries = ["", "   ", ids[0], "missing", f"{ids[0]},ODD"]
    for _ in range(120):
        start = rng.choice(ids) if rng.random() > 0.1 else "does-not-exist"
        queries.append(",".join([start] + [rng.choice(edge_types) for _ in range(rng.randint(0, 7))]))

    nodes_data = "\n".join(node_lines) + "\n"
    edges_data = "\n".join(edge_lines) + "\n"
    stdin_data = "\n".join(queries) + "\n"

    with tempfile.TemporaryDirectory() as tmp:
        os.chmod(tmp, 0o755)
        nodes_path = os.path.join(tmp, "nodes.csv")
        edges_path = os.path.join(tmp, "edges.csv")
        with open(nodes_path, "w") as f:
            f.write(nodes_data)
        with open(edges_path, "w") as f:
            f.write(edges_data)
        os.chmod(nodes_path, 0o644)
        os.chmod(edges_path, 0o644)
        try:
            result = subprocess.run(
                [agent, nodes_path, edges_path], input=stdin_data, text=True,
                capture_output=True, timeout=10, preexec_fn=demote
            )
        except subprocess.TimeoutExpired:
            raise AssertionError(f"rebuilt program timed out on iteration {iteration}")
        assert result.returncode == 0, f"rebuilt program exited {result.returncode}: {result.stderr}"
        wanted = expected(nodes_data, edges_data, stdin_data)
        assert result.stdout == wanted, f"independent output mismatch on iteration {iteration}"
INDEPENDENT_EOF

    cleanup
    HOLD_DIR=""
    return 0
}

if run_checks; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
