#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
from contextlib import contextmanager

import pytest

SCRIPT_PATH = "/home/user/app/handler.sh"
DB_PATH = "/home/user/app/packages.db"


def run_handler(input_string: str) -> str:
    """Run the submitted handler with the supplied WebSocket message."""
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script at {SCRIPT_PATH} is not executable"

    result = subprocess.run(
        [SCRIPT_PATH],
        input=input_string,
        text=True,
        capture_output=True,
        timeout=5,
    )
    return result.stdout.strip()


def test_handler_successful_resolution():
    """Test that the handler correctly resolves a complex dependency graph and formats the output."""
    input_str = "RESOLVE /api/deps?foo=bar&pkg=web_server&baz=1"
    try:
        output = run_handler(input_str)
    except subprocess.TimeoutExpired:
        pytest.fail("The script timed out, likely due to an infinite loop.")

    expected = "SUCCESS: config disk filesystem http logger network system tcp"
    assert output == expected, f"Expected output '{expected}', but got '{output}'"


def test_handler_cycle_detection():
    """Test that the handler detects circular dependencies and halts with the correct error message."""
    input_str = "RESOLVE /api/deps?pkg=auth"
    try:
        output = run_handler(input_str)
    except subprocess.TimeoutExpired:
        pytest.fail("The script timed out on a circular dependency instead of detecting it.")

    expected = "ERROR: cycle detected"
    assert output == expected, f"Expected output '{expected}', but got '{output}'"


def test_handler_parameter_parsing_edge_cases():
    """Test that the handler correctly extracts the pkg parameter from various positions."""
    out1 = run_handler("RESOLVE /api/deps?verbose=1&pkg=tcp")
    assert out1 == "SUCCESS: filesystem logger network system", f"Failed on pkg at end. Got: {out1}"

    out2 = run_handler("RESOLVE /api/deps?pkg=tcp&verbose=1")
    assert out2 == "SUCCESS: filesystem logger network system", f"Failed on pkg at beginning. Got: {out2}"

    out3 = run_handler("RESOLVE /api/deps?pkg=tcp")
    assert out3 == "SUCCESS: filesystem logger network system", f"Failed on pkg as only parameter. Got: {out3}"


def parse_database(contents: str):
    graph = {}
    for raw_line in contents.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        package, separator, dependencies = line.partition(":")
        assert separator == ":"
        graph[package.strip()] = dependencies.split()
    return graph


def expected_resolution(contents: str, requested: str) -> str:
    """Independently derive the required result from the temporary database."""
    graph = parse_database(contents)
    found = set()
    active = set()

    def visit(package):
        if package in active:
            raise ValueError("cycle")
        active.add(package)
        for dependency in graph.get(package, []):
            found.add(dependency)
            visit(dependency)
        active.remove(package)

    try:
        visit(requested)
    except ValueError:
        return "ERROR: cycle detected"
    return "SUCCESS: " + " ".join(sorted(found))


@contextmanager
def temporary_database(contents: str):
    with open(DB_PATH, "r", encoding="utf-8") as handle:
        original = handle.read()
    try:
        with open(DB_PATH, "w", encoding="utf-8") as handle:
            handle.write(contents)
        yield
    finally:
        with open(DB_PATH, "w", encoding="utf-8") as handle:
            handle.write(original)


def test_dynamic_dependency_graph_and_cycle_detection():
    """Exercise arbitrary names, shared DAG nodes, unrelated nodes, and a fresh cycle."""
    token = secrets.token_hex(8)
    names = [f"pkg_{token}_{index}" for index in range(14)]

    graph = {
        names[0]: [names[1], names[2], names[1]],
        names[1]: [names[3], names[4]],
        names[2]: [names[4], names[5]],
        names[3]: [names[6]],
        names[4]: [names[7]],
        names[5]: [names[7]],
        names[6]: [names[8]],
        names[7]: [names[8]],
        names[8]: [],
        names[9]: [names[10]],
        names[10]: [],
        names[11]: [names[12]],
        names[12]: [names[13]],
        names[13]: [names[12]],
    }

    rng = secrets.SystemRandom()
    rows = []
    for package, dependencies in graph.items():
        shuffled_dependencies = list(dependencies)
        rng.shuffle(shuffled_dependencies)
        rows.append(f"{package}: {' '.join(shuffled_dependencies)}")
    rng.shuffle(rows)
    database = "\n".join(rows) + "\n"

    with temporary_database(database):
        request = f"RESOLVE /api/deps?verbose=1&pkg={names[0]}&format=text"
        output = run_handler(request)
        expected = expected_resolution(database, names[0])
        assert output == expected, f"Dynamic root resolution expected '{expected}', got '{output}'"

        request = f"RESOLVE /api/deps?pkg={names[2]}&other=value"
        output = run_handler(request)
        expected = expected_resolution(database, names[2])
        assert output == expected, f"Dynamic subgraph resolution expected '{expected}', got '{output}'"

        request = f"RESOLVE /api/deps?mode=full&pkg={names[9]}"
        output = run_handler(request)
        expected = expected_resolution(database, names[9])
        assert output == expected, f"Unrelated subgraph resolution expected '{expected}', got '{output}'"

        try:
            output = run_handler(f"RESOLVE /api/deps?x=1&pkg={names[11]}&y=2")
        except subprocess.TimeoutExpired:
            pytest.fail("The script timed out on the dynamically generated circular dependency.")
        expected = expected_resolution(database, names[11])
        assert expected == "ERROR: cycle detected"
        assert output == expected, f"Dynamic cycle expected '{expected}', got '{output}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
