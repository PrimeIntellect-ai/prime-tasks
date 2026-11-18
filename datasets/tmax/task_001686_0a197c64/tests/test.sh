#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def parse_version(v):
    return tuple(map(int, v.split('.')))

def check_constraint(available_version, constraint):
    op, req_v = constraint.split(' ')
    av = parse_version(available_version)
    rv = parse_version(req_v)
    if op == '==': return av == rv
    if op == '>=': return av >= rv
    if op == '<=': return av <= rv
    if op == '>': return av > rv
    if op == '<': return av < rv
    return False

def get_expected():
    packages_dir = "/home/user/packages"
    packages = {}
    if not os.path.exists(packages_dir):
        return [], []

    for entry in os.listdir(packages_dir):
        pkg_dir = os.path.join(packages_dir, entry)
        if os.path.isdir(pkg_dir):
            pkg_info_path = os.path.join(pkg_dir, "pkg_info.json")
            if os.path.isfile(pkg_info_path):
                with open(pkg_info_path) as f:
                    data = json.load(f)
                    packages[data["name"]] = data

    # Find unresolvable packages (cascading)
    dropped = set()
    while True:
        new_dropped = set()
        for name, data in packages.items():
            if name in dropped:
                continue
            for dep, constraint in data.get("dependencies", {}).items():
                if dep not in packages or dep in dropped:
                    new_dropped.add(name)
                    break
                if not check_constraint(packages[dep]["version"], constraint):
                    new_dropped.add(name)
                    break
        if not new_dropped:
            break
        dropped.update(new_dropped)

    valid_packages = {name: data for name, data in packages.items() if name not in dropped}

    # Topological sort with alphabetical tie-breaking
    in_degree = {name: 0 for name in valid_packages}
    adj = {name: [] for name in valid_packages}

    for name, data in valid_packages.items():
        for dep in data.get("dependencies", {}):
            if dep in adj:
                adj[dep].append(name)
                in_degree[name] += 1

    build_order = []
    # Find all nodes with 0 in-degree
    queue = [name for name in valid_packages if in_degree[name] == 0]

    while queue:
        queue.sort()  # Tie-breaking rule: alphabetical
        curr = queue.pop(0)
        build_order.append(curr)
        for nxt in adj[curr]:
            in_degree[nxt] -= 1
            if in_degree[nxt] == 0:
                queue.append(nxt)

    return build_order, sorted(list(dropped))

def test_build_order_file():
    expected_build_order, _ = get_expected()
    path = "/home/user/build_order.txt"
    assert os.path.exists(path), f"File {path} does not exist. The script must create this file."

    with open(path, "r") as f:
        actual = [line.strip() for line in f if line.strip()]

    assert actual == expected_build_order, (
        f"Build order in {path} does not match the expected topological sort.\n"
        f"Expected: {expected_build_order}\n"
        f"Actual:   {actual}"
    )

def test_dropped_file():
    _, expected_dropped = get_expected()
    path = "/home/user/dropped.txt"
    assert os.path.exists(path), f"File {path} does not exist. The script must create this file."

    with open(path, "r") as f:
        actual = [line.strip() for line in f if line.strip()]

    assert actual == expected_dropped, (
        f"Dropped packages in {path} do not match the expected list.\n"
        f"Expected: {expected_dropped}\n"
        f"Actual:   {actual}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
