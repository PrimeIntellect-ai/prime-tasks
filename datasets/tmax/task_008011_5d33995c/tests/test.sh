#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import sqlite3
import subprocess
import pytest

SCRIPT_PATH = "/home/user/backup_neighborhood.sh"
DB_PATH = "/home/user/graph.db"


def load_and_check_pretty(path):
    with open(path, "r", encoding="utf-8") as f:
        raw = f.read()
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        pytest.fail(f"Output file {path} is not valid JSON")

    assert len(raw.splitlines()) > 1, "Output JSON is not pretty-printed"
    assert re.search(r'^  "center_node"\s*:', raw, re.MULTILINE), \
        "Output JSON does not use pretty-print indentation"
    return data


def assert_strict_structure(data, center, expected_nodes, expected_edges):
    assert type(data) is dict
    assert set(data.keys()) == {"center_node", "nodes", "edges"}
    assert type(data["center_node"]) is int
    assert data["center_node"] == center
    assert type(data["nodes"]) is list
    assert type(data["edges"]) is list

    for node in data["nodes"]:
        assert type(node) is dict
        assert set(node.keys()) == {"id", "data"}
        assert type(node["id"]) is int
        assert type(node["data"]) is str

    for edge in data["edges"]:
        assert type(edge) is dict
        assert set(edge.keys()) == {"source", "target", "type"}
        assert type(edge["source"]) is int
        assert type(edge["target"]) is int
        assert type(edge["type"]) is str

    assert data["nodes"] == expected_nodes
    assert data["edges"] == expected_edges


def expected_from_database(center):
    with sqlite3.connect(DB_PATH) as db:
        edges = [
            {"source": src, "target": dst, "type": relation}
            for src, dst, relation in db.execute(
                "SELECT src, dst, relation_name FROM link "
                "WHERE src = ? OR dst = ? ORDER BY src ASC, dst ASC",
                (center, center),
            )
        ]
        nodes = [
            {"id": node_id, "data": attributes}
            for node_id, attributes in db.execute(
                "SELECT v_id, attributes FROM vertex WHERE v_id IN ("
                "SELECT ? UNION SELECT src FROM link WHERE dst = ? "
                "UNION SELECT dst FROM link WHERE src = ?"
                ") ORDER BY v_id ASC",
                (center, center, center),
            )
        ]
    return nodes, edges


def run_script(center):
    output_file = f"/home/user/backup_{center}.json"
    if os.path.exists(output_file):
        os.remove(output_file)
    result = subprocess.run(
        [SCRIPT_PATH, str(center)], capture_output=True, text=True, timeout=20
    )
    assert result.returncode == 0, f"Script failed with error: {result.stderr}"
    assert os.path.isfile(output_file), f"Output file {output_file} was not created"
    return load_and_check_pretty(output_file)


def test_script_exists_and_executable():
    """Verify the bash script exists and is executable."""
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable"
    with open(SCRIPT_PATH, "r", encoding="utf-8", errors="replace") as f:
        source = f.read()
    assert source.startswith("#!") and "bash" in source.splitlines()[0], \
        "The submitted artifact must be a Bash script"
    assert re.search(r"\bsqlite3\b", source), "The script must use sqlite3"
    assert re.search(r"\bjq\b", source), "The script must use jq"


def test_script_output_node_10():
    """Run the script for node 10 and verify the output."""
    result = subprocess.run([SCRIPT_PATH, "10"], capture_output=True, text=True)
    assert result.returncode == 0, f"Script failed with error: {result.stderr}"

    output_file = "/home/user/backup_10.json"
    assert os.path.isfile(output_file), f"Output file {output_file} was not created"
    data = load_and_check_pretty(output_file)

    assert data.get("center_node") == 10, "center_node is incorrect"

    expected_edges = [
        {"source": 10, "target": 20, "type": "MANAGES"},
        {"source": 10, "target": 40, "type": "INVITED"},
        {"source": 30, "target": 10, "type": "REPORTS_TO"}
    ]
    expected_nodes = [
        {"id": 10, "data": '{"name": "Alice", "role": "admin"}'},
        {"id": 20, "data": '{"name": "Bob", "role": "user"}'},
        {"id": 30, "data": '{"name": "Charlie", "role": "user"}'},
        {"id": 40, "data": '{"name": "David", "role": "guest"}'}
    ]

    assert data.get("edges") == expected_edges, "Edges array is incorrect or not sorted properly for node 10"
    assert data.get("nodes") == expected_nodes, "Nodes array is incorrect or not sorted properly for node 10"


def test_script_output_node_20():
    """Run the script for node 20 to ensure it dynamically handles different inputs."""
    result = subprocess.run([SCRIPT_PATH, "20"], capture_output=True, text=True)
    assert result.returncode == 0, f"Script failed with error: {result.stderr}"

    output_file = "/home/user/backup_20.json"
    assert os.path.isfile(output_file), f"Output file {output_file} was not created"
    data = load_and_check_pretty(output_file)

    assert data.get("center_node") == 20, "center_node is incorrect"

    expected_edges = [
        {"source": 10, "target": 20, "type": "MANAGES"},
        {"source": 20, "target": 30, "type": "KNOWS"},
        {"source": 40, "target": 20, "type": "KNOWS"}
    ]
    expected_nodes = [
        {"id": 10, "data": '{"name": "Alice", "role": "admin"}'},
        {"id": 20, "data": '{"name": "Bob", "role": "user"}'},
        {"id": 30, "data": '{"name": "Charlie", "role": "user"}'},
        {"id": 40, "data": '{"name": "David", "role": "guest"}'}
    ]

    assert data.get("edges") == expected_edges, "Edges array is incorrect or not sorted properly for node 20"
    assert data.get("nodes") == expected_nodes, "Nodes array is incorrect or not sorted properly for node 20"


def test_dynamic_database_neighborhood_and_tool_execution():
    """Exercise an unpredictable neighborhood whose answer is derived from SQLite."""
    token = secrets.token_hex(12)
    with sqlite3.connect(DB_PATH) as db:
        maximum = db.execute("SELECT COALESCE(MAX(v_id), 0) FROM vertex").fetchone()[0]
        center = maximum + 1000 + secrets.randbelow(1000000)
        ids = [center + i for i in range(5)]
        values = [
            (ids[0], f'{{"dynamic":"center-{token}"}}'),
            (ids[1], f'neighbor-one:{token}'),
            (ids[2], f'neighbor-two:{token}'),
            (ids[3], f'neighbor-three:{token}'),
            (ids[4], f'unrelated:{token}'),
        ]
        db.executemany("INSERT INTO vertex(v_id, attributes) VALUES (?, ?)", values)
        db.executemany(
            "INSERT INTO link(src, dst, relation_name) VALUES (?, ?, ?)",
            [
                (ids[0], ids[1], f"OUT_A_{token}"),
                (ids[2], ids[0], f"IN_B_{token}"),
                (ids[0], ids[3], f"OUT_C_{token}"),
                (ids[3], ids[2], f"EXCLUDED_{token}"),
            ],
        )

    expected_nodes, expected_edges = expected_from_database(center)
    data = run_script(center)
    assert_strict_structure(data, center, expected_nodes, expected_edges)

    # Change the live database and rerun the same argument, ensuring output is
    # freshly queried rather than selected from fixed constants or cached data.
    replacement = f'changed-after-first-run:{secrets.token_hex(10)}'
    new_relation = f"UPDATED_{secrets.token_hex(10)}"
    with sqlite3.connect(DB_PATH) as db:
        db.execute("UPDATE vertex SET attributes = ? WHERE v_id = ?", (replacement, ids[1]))
        db.execute(
            "UPDATE link SET relation_name = ? WHERE src = ? AND dst = ?",
            (new_relation, ids[0], ids[1]),
        )

    expected_nodes, expected_edges = expected_from_database(center)
    data = run_script(center)
    assert_strict_structure(data, center, expected_nodes, expected_edges)

    # Bash tracing confirms both required command-line tools are actually run.
    traced = subprocess.run(
        ["/bin/bash", "-x", SCRIPT_PATH, str(center)],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert traced.returncode == 0, f"Traced script run failed: {traced.stderr}"
    assert re.search(r"^\++\s+(?:command\s+)?(?:\S*/)?sqlite3(?:\s|$)", traced.stderr, re.MULTILINE), \
        "The script did not execute sqlite3"
    assert re.search(r"^\++\s+(?:command\s+)?(?:\S*/)?jq(?:\s|$)", traced.stderr, re.MULTILINE), \
        "The script did not execute jq"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
