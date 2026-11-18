#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fnmatch
import json
import os
import random
import subprocess
import pytest

AGENT_EXECUTABLE = "/home/user/backup_planner"
N_ITERATIONS = 50
BASE_MTIME = 1700000000


def match_exclude(path):
    return any(fnmatch.fnmatch(path, pattern) for pattern in (
        "*.tmp",
        "*cache/*",
        "/var/log*",
    ))


def parent_path(path):
    if path == "/":
        return None
    stripped = path.rstrip("/")
    parent = stripped.rsplit("/", 1)[0]
    return parent or "/"


def reference_output(data):
    nodes = {node["path"]: node for node in data}
    roots = sorted(
        path for path, node in nodes.items()
        if node.get("type") == "directory"
        and (path == "/" or parent_path(path) not in nodes)
    )

    children = {}
    for path in nodes:
        parent = parent_path(path)
        if parent is not None:
            children.setdefault(parent, []).append(path)
    for paths in children.values():
        paths.sort()

    output = []
    active_resolved_paths = set()

    def dfs(resolved_path, logical_path):
        if resolved_path in active_resolved_paths:
            return

        node = nodes.get(resolved_path)
        if node is None or match_exclude(logical_path):
            return

        active_resolved_paths.add(resolved_path)
        try:
            node_type = node.get("type")
            if node_type == "file":
                mtime = node.get("mtime", 0)
                if mtime > BASE_MTIME:
                    output.append(f"{logical_path},{mtime}")
            elif node_type == "symlink":
                target = node.get("target")
                if target is not None:
                    dfs(target, logical_path)
            elif node_type == "directory":
                for child in children.get(resolved_path, []):
                    name = child.rstrip("/").rsplit("/", 1)[-1]
                    child_logical = (
                        "/" + name if logical_path == "/"
                        else logical_path.rstrip("/") + "/" + name
                    )
                    dfs(child, child_logical)
        finally:
            active_resolved_paths.remove(resolved_path)

    for root in roots:
        dfs(root, root)

    return "\n".join(output)


def generate_random_vfs(seed):
    random.seed(seed)
    num_nodes = random.randint(10, 150)

    nodes = []
    dirs = ["/"]
    nodes.append({"path": "/", "type": "directory"})

    for i in range(1, num_nodes):
        parent = random.choice(dirs)
        name = f"node_{i}"
        path = f"{parent}{name}" if parent == "/" else f"{parent}/{name}"

        node_type = random.choices(
            ["directory", "file", "symlink"], weights=[0.3, 0.6, 0.1]
        )[0]

        if random.random() < 0.1:
            name = random.choice(["cache", "var", "log"])
            path = f"{parent}{name}" if parent == "/" else f"{parent}/{name}"
            if name == "var":
                path = "/var/log"
                node_type = "directory"

        if node_type == "directory":
            nodes.append({"path": path, "type": "directory"})
            dirs.append(path)
        elif node_type == "file":
            mtime = random.randint(1699990000, 1700010000)
            if random.random() < 0.2:
                path += ".tmp"
            nodes.append({"path": path, "type": "file", "mtime": mtime})
        else:
            target = random.choice(dirs)
            nodes.append({"path": path, "type": "symlink", "target": target})

    random.shuffle(nodes)
    return nodes


def test_agent_executable_exists():
    assert os.path.isfile(AGENT_EXECUTABLE), f"Agent executable missing: {AGENT_EXECUTABLE}"
    assert os.access(AGENT_EXECUTABLE, os.X_OK), f"Agent executable is not executable: {AGENT_EXECUTABLE}"


@pytest.mark.parametrize("seed", range(N_ITERATIONS))
def test_fuzz_equivalence(seed):
    vfs = generate_random_vfs(seed)
    input_json = json.dumps(vfs)
    expected = reference_output(vfs)

    agent_proc = subprocess.run(
        [AGENT_EXECUTABLE],
        input=input_json,
        text=True,
        capture_output=True,
    )

    assert agent_proc.returncode == 0, f"Agent failed on seed {seed}:\n{agent_proc.stderr}"

    agent_out = agent_proc.stdout.strip()
    if expected != agent_out:
        pytest.fail(
            f"Mismatch on seed {seed}.\n"
            f"Input JSON:\n{input_json}\n\n"
            f"Expected Output:\n{expected}\n\n"
            f"Agent Output:\n{agent_out}\n"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
