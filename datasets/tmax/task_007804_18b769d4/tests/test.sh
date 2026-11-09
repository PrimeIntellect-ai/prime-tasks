#!/bin/bash
mkdir -p /logs/verifier

if (
    set -e

    # Require a real, syntactically valid Python script at the requested path.
    python3 - <<'PY'
import os
import stat

path = "/home/user/build_mgr.py"
st = os.lstat(path)
assert stat.S_ISREG(st.st_mode), f"{path} must be a regular file"
PY
    python3 -m py_compile /home/user/build_mgr.py

    # Restore the immutable task inputs and a clean initial state before executing
    # the submitted artifact, so mutable deps.json cannot make checks vacuous.
    rm -f /home/user/deps.json /home/user/artifacts.db
    rm -rf /home/user/artifacts

    cat <<'DEPS_EOF' > /home/user/deps.json
{
  "frontend": ["api", "utils"],
  "api": ["database", "auth"],
  "auth": ["utils", "database"],
  "database": ["core"],
  "utils": ["core"],
  "core": []
}
DEPS_EOF

    sqlite3 /home/user/artifacts.db "CREATE TABLE packages (name TEXT PRIMARY KEY, language TEXT);"
    sqlite3 /home/user/artifacts.db "INSERT INTO packages (name, language) VALUES ('frontend', 'javascript'), ('api', 'go'), ('auth', 'python'), ('database', 'c++'), ('utils', 'python'), ('core', 'c');"
    chown user:user /home/user/deps.json /home/user/artifacts.db

    # Execute the script as the task user against the clean initial state.
    runuser -u user -- bash -c 'cd /home/user && timeout 20s python3 /home/user/build_mgr.py'

    cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import sqlite3
import heapq
import stat
import pytest

DEPS_JSON_PATH = "/home/user/deps.json"
DB_PATH = "/home/user/artifacts.db"
ARTIFACTS_DIR = "/home/user/artifacts"
SCRIPT_PATH = "/home/user/build_mgr.py"

EXPECTED_DEPS = {
    "frontend": ["api", "utils"],
    "api": ["database", "auth"],
    "auth": ["utils", "database"],
    "database": ["core"],
    "utils": ["core"],
    "core": [],
}


def get_expected_build_order():
    """Derive the expected order using the required alphabetical tie-breaking."""
    assert os.path.exists(DEPS_JSON_PATH), f"Missing {DEPS_JSON_PATH}"
    with open(DEPS_JSON_PATH, "r") as f:
        deps = json.load(f)

    assert deps == EXPECTED_DEPS, f"{DEPS_JSON_PATH} was modified"

    in_degree = {pkg: 0 for pkg in deps}
    graph = {pkg: [] for pkg in deps}

    for pkg, pkg_deps in deps.items():
        in_degree[pkg] = len(pkg_deps)
        for dep in pkg_deps:
            if dep not in graph:
                graph[dep] = []
                in_degree[dep] = 0
            graph[dep].append(pkg)

    ready = [pkg for pkg, deg in in_degree.items() if deg == 0]
    heapq.heapify(ready)

    build_order = []
    while ready:
        curr = heapq.heappop(ready)
        build_order.append(curr)
        for neighbor in graph.get(curr, []):
            in_degree[neighbor] -= 1
            if in_degree[neighbor] == 0:
                heapq.heappush(ready, neighbor)

    assert len(build_order) == len(in_degree), "Dependency graph is not fully sortable"
    return build_order


def test_build_manager_script_exists():
    st = os.lstat(SCRIPT_PATH)
    assert stat.S_ISREG(st.st_mode), f"{SCRIPT_PATH} must be a regular file"


def test_dependency_input_unchanged():
    with open(DEPS_JSON_PATH, "r") as f:
        assert json.load(f) == EXPECTED_DEPS


def test_database_schema_updated():
    """Verify that build_order of type INTEGER was added to packages."""
    assert os.path.exists(DB_PATH), f"{DB_PATH} does not exist"
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("PRAGMA table_info(packages);")
    columns = {row[1]: row[2] for row in cursor.fetchall()}
    conn.close()

    assert "build_order" in columns, "Column 'build_order' is missing from 'packages' table"
    assert columns["build_order"].upper() == "INTEGER", "Column 'build_order' should be of type INTEGER"


def test_database_build_order_values():
    """Verify the 1-based build order for every original package."""
    expected_order = get_expected_build_order()

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT name, build_order FROM packages;")
    rows = cursor.fetchall()
    conn.close()

    db_build_order = {row[0]: row[1] for row in rows}
    assert set(db_build_order) == set(EXPECTED_DEPS), "The packages table package set was modified"

    for i, pkg in enumerate(expected_order, start=1):
        assert pkg in db_build_order, f"Package '{pkg}' missing from database"
        assert db_build_order[pkg] == i, f"Expected build_order for '{pkg}' to be {i}, got {db_build_order[pkg]}"


def test_mock_artifact_files():
    """Verify each mock artifact's name and exact content."""
    expected_order = get_expected_build_order()
    assert os.path.isdir(ARTIFACTS_DIR), f"Directory {ARTIFACTS_DIR} does not exist"

    for pkg in expected_order:
        mock_file = os.path.join(ARTIFACTS_DIR, f"{pkg}.mock")
        assert os.path.isfile(mock_file), f"Mock artifact file {mock_file} is missing"

        with open(mock_file, "r") as f:
            raw_content = f.read()

        expected_content = f"MOCK_BUILD_{pkg}"
        assert raw_content.strip() == expected_content, (
            f"Content of {mock_file} is incorrect. Expected '{expected_content}', got '{raw_content.strip()}'"
        )
        assert raw_content == expected_content, f"Content of {mock_file} must match exactly"
TEST_EOF

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short
); then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
