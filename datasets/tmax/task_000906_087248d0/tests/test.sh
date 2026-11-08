#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import hashlib
import pytest

def compute_hash(target, graph, cache):
    if target in cache:
        return cache[target]

    if target not in graph:
        raise ValueError(f"Target '{target}' not found in build graph.")

    deps, cmd = graph[target]

    # Sort dependencies alphabetically by target name
    sorted_deps = sorted(deps)

    dep_hashes = []
    for dep in sorted_deps:
        dep_hashes.append(compute_hash(dep, graph, cache))

    string_to_hash = cmd + "".join(dep_hashes)
    h = hashlib.sha256(string_to_hash.encode('utf-8')).hexdigest()
    cache[target] = h
    return h

def test_cache_key_file_exists():
    path = "/home/user/cache_key.txt"
    assert os.path.isfile(path), f"File {path} does not exist. The Rust program must write the output to this file."

def test_cache_key_correctness():
    graph_path = "/home/user/build_graph.txt"
    assert os.path.isfile(graph_path), f"Missing {graph_path}"

    graph = {}
    with open(graph_path, 'r') as f:
        for line in f:
            line = line.strip('\n')
            if not line: 
                continue

            if '|' not in line:
                continue

            target_part, cmd_part = line.split('|', 1)

            # Command starts exactly one space after the '|' character
            cmd = cmd_part[1:] if cmd_part.startswith(' ') else cmd_part

            target_name, deps_str = target_part.split(':', 1)
            target_name = target_name.strip()
            deps = deps_str.split()

            graph[target_name] = (deps, cmd)

    cache = {}
    expected_hash = compute_hash("release_bin", graph, cache)

    key_path = "/home/user/cache_key.txt"
    with open(key_path, 'r') as f:
        actual_hash = f.read().strip()

    assert actual_hash == expected_hash, f"Incorrect cache key. Expected '{expected_hash}', but got '{actual_hash}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
