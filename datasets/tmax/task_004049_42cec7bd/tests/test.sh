#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import json
import os
import random
import re
import secrets
import shutil
import sqlite3
import subprocess

import pytest

PROJECT = "/home/user/audit"
SOURCE = os.path.join(PROJECT, "src", "main.rs")
SYSTEMS = os.path.join(PROJECT, "systems.json")
DATABASE = os.path.join(PROJECT, "access.db")
OUTPUT = os.path.join(PROJECT, "shortest_path.txt")


@pytest.fixture(scope="session", autouse=True)
def restore_inputs():
    systems_backup = open(SYSTEMS, "rb").read()
    database_backup = open(DATABASE, "rb").read()
    yield
    with open(SYSTEMS, "wb") as f:
        f.write(systems_backup)
    with open(DATABASE, "wb") as f:
        f.write(database_backup)


def run_program():
    if os.path.lexists(OUTPUT):
        os.unlink(OUTPUT)
    result = subprocess.run(
        ["cargo", "run", "--quiet"],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert result.returncode == 0, (
        f"cargo run failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def read_result():
    assert os.path.isfile(OUTPUT), "The Rust program did not create shortest_path.txt"
    content = open(OUTPUT, "r").read().strip()
    assert re.fullmatch(r"-?\d+", content), f"Output is not an integer: {content!r}"
    return int(content)


def expected_distance(systems, links):
    ids = {entry["name"]: entry["id"] for entry in systems}
    start, target = ids["PublicWeb"], ids["SecureVault"]
    graph = collections.defaultdict(list)
    for source, destination, protocol in links:
        if protocol == "SSH":
            graph[source].append(destination)
    queue = collections.deque([(start, 0)])
    seen = {start}
    while queue:
        node, distance = queue.popleft()
        if node == target:
            return distance
        for neighbor in graph[node]:
            if neighbor not in seen:
                seen.add(neighbor)
                queue.append((neighbor, distance + 1))
    return -1


def install_case(systems, links):
    with open(SYSTEMS, "w") as f:
        json.dump(systems, f)
    temporary_db = DATABASE + ".verifier_tmp"
    if os.path.exists(temporary_db):
        os.unlink(temporary_db)
    connection = sqlite3.connect(temporary_db)
    try:
        connection.execute(
            "CREATE TABLE network_links "
            "(source_id INTEGER, target_id INTEGER, protocol TEXT)"
        )
        connection.executemany(
            "INSERT INTO network_links VALUES (?, ?, ?)", links
        )
        connection.commit()
    finally:
        connection.close()
    os.replace(temporary_db, DATABASE)


def test_rust_source_and_parameterized_query():
    assert os.path.isfile(SOURCE), f"Missing Rust source file: {SOURCE}"
    source = open(SOURCE, "r").read()
    assert "fn main" in source, "src/main.rs does not define a Rust main function"
    placeholder = r"(?:\?[0-9]*|[:@$][A-Za-z_][A-Za-z0-9_]*)"
    parameterized_protocol = re.search(
        rf"protocol\s*(?:=|IS)\s*{placeholder}|"
        rf"protocol\s+IN\s*\(\s*{placeholder}|"
        rf"{placeholder}\s*(?:=|IS)\s*protocol",
        source,
        flags=re.IGNORECASE | re.DOTALL,
    )
    assert "network_links" in source and parameterized_protocol, (
        "The network_links SQL query must filter protocol using a SQL parameter placeholder"
    )


def test_shortest_path_result():
    run_program()
    path_file = "/home/user/audit/shortest_path.txt"
    assert os.path.isfile(path_file), f"The file {path_file} does not exist. Did you run your Rust program?"

    with open(path_file, "r") as f:
        content = f.read().strip()

    assert content == "3", f"Expected shortest path length to be '3', but got '{content}'."


def test_program_uses_json_database_protocol_direction_and_bfs():
    base = secrets.randbelow(1_000_000_000) + 100_000
    names = ["PublicWeb", "SecureVault", "RelayA", "RelayB", "RelayC", "Noise"]
    values = random.sample(range(base, base + 10000), len(names))
    ids = dict(zip(names, values))
    systems = [{"id": ids[name], "name": name} for name in names]
    random.shuffle(systems)

    cases = [
        [
            (ids["PublicWeb"], ids["RelayA"], "SSH"),
            (ids["RelayA"], ids["RelayB"], "SSH"),
            (ids["RelayB"], ids["RelayC"], "SSH"),
            (ids["RelayC"], ids["SecureVault"], "SSH"),
            (ids["PublicWeb"], ids["SecureVault"], "HTTP"),
            (ids["PublicWeb"], ids["RelayB"], "ssh"),
            (ids["SecureVault"], ids["PublicWeb"], "SSH"),
        ],
        [
            (ids["PublicWeb"], ids["RelayA"], "SSH"),
            (ids["RelayA"], ids["SecureVault"], "HTTPS"),
            (ids["SecureVault"], ids["PublicWeb"], "SSH"),
            (ids["RelayB"], ids["SecureVault"], "SSH"),
        ],
        [
            (ids["PublicWeb"], ids["SecureVault"], "SSH"),
            (ids["PublicWeb"], ids["RelayA"], "SSH"),
            (ids["RelayA"], ids["RelayB"], "SSH"),
            (ids["RelayB"], ids["SecureVault"], "SSH"),
        ],
    ]

    for links in cases:
        install_case(systems, links)
        expected = expected_distance(systems, links)
        run_program()
        assert read_result() == expected
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
