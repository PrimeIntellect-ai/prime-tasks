#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import sqlite3
import subprocess

SCRIPT_PATH = "/home/user/build_graph.sh"
CYPHER_PATH = "/home/user/insert.cypher"
DB_PATH = "/home/user/pipeline.db"

EXPECTED_CYPHER = """MERGE (n:Asset {id: 1, name: 'Root'});
MERGE (n:Asset {id: 2, name: 'Node_A'});
MERGE (n:Asset {id: 3, name: 'Node_B'});
MERGE (n:Asset {id: 4, name: 'Node_AA'});
MERGE (n:Asset {id: 5, name: 'Node_AB'});
MERGE (n:Asset {id: 6, name: 'Node_AAA'});
MERGE (n:Asset {id: 8, name: 'Node_C'});
MERGE (c:Asset {id: 2})-[:HAS_PARENT]->(p:Asset {id: 1});
MERGE (c:Asset {id: 3})-[:HAS_PARENT]->(p:Asset {id: 1});
MERGE (c:Asset {id: 4})-[:HAS_PARENT]->(p:Asset {id: 2});
MERGE (c:Asset {id: 5})-[:HAS_PARENT]->(p:Asset {id: 2});
MERGE (c:Asset {id: 6})-[:HAS_PARENT]->(p:Asset {id: 4});
MERGE (c:Asset {id: 8})-[:HAS_PARENT]->(p:Asset {id: 1});
"""


def normalized_lines(text):
    return [line.strip() for line in text.strip().split('\n') if line.strip()]


def assert_index_rebuilt():
    with sqlite3.connect(DB_PATH) as conn:
        row = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_parent'"
        ).fetchone()
        assert row == ("idx_parent",), "idx_parent was not recreated/rebuilt"

        columns = conn.execute("PRAGMA index_info('idx_parent')").fetchall()
        assert [column[2] for column in columns] == ["parent_id"], (
            "idx_parent does not index assets(parent_id)"
        )

        integrity = [row[0] for row in conn.execute("PRAGMA integrity_check").fetchall()]
        assert integrity == ["ok"], f"Database/index integrity check failed: {integrity}"

        indexed = conn.execute(
            "SELECT id, name, parent_id FROM assets INDEXED BY idx_parent "
            "ORDER BY parent_id, id"
        ).fetchall()
        unindexed = conn.execute(
            "SELECT id, name, parent_id FROM assets NOT INDEXED "
            "ORDER BY parent_id, id"
        ).fetchall()
        assert indexed == unindexed, "idx_parent returns data inconsistent with the table"


def expected_from_database():
    with sqlite3.connect(DB_PATH) as conn:
        rows = conn.execute(
            "SELECT id, name, parent_id FROM assets NOT INDEXED"
        ).fetchall()

    by_parent = {}
    by_id = {}
    for asset_id, name, parent_id in rows:
        by_id[asset_id] = (name, parent_id)
        by_parent.setdefault(parent_id, []).append(asset_id)

    assert 1 in by_id, "Dynamic fixture is missing root id 1"
    depths = {1: 0}
    queue = [1]
    while queue:
        parent = queue.pop(0)
        depth = depths[parent]
        if depth == 3:
            continue
        for child in by_parent.get(parent, []):
            if child not in depths:
                depths[child] = depth + 1
                queue.append(child)

    included = sorted(depths)
    lines = [
        f"MERGE (n:Asset {{id: {asset_id}, name: '{by_id[asset_id][0]}'}});"
        for asset_id in included
    ]
    lines.extend(
        f"MERGE (c:Asset {{id: {asset_id}}})-[:HAS_PARENT]->"
        f"(p:Asset {{id: {by_id[asset_id][1]}}});"
        for asset_id in included
        if asset_id != 1
    )
    return lines


def test_script_exists_and_executable():
    """Check if the bash script exists and is executable."""
    assert os.path.isfile(SCRIPT_PATH), f"Script missing at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script at {SCRIPT_PATH} is not executable"

    with open(SCRIPT_PATH, "r", encoding="utf-8") as script_file:
        source = script_file.read()
    assert re.search(r"\bWITH\s+RECURSIVE\b", source, re.IGNORECASE), (
        "The script must execute a WITH RECURSIVE hierarchical query"
    )


def test_script_execution_and_output():
    """Run the script and verify the generated Cypher script."""
    if os.path.exists(CYPHER_PATH):
        os.remove(CYPHER_PATH)

    result = subprocess.run([SCRIPT_PATH], capture_output=True, text=True)
    assert result.returncode == 0, f"Script failed to execute. stderr: {result.stderr}"

    assert os.path.isfile(CYPHER_PATH), f"Cypher script was not generated at {CYPHER_PATH}"

    with open(CYPHER_PATH, 'r') as f:
        actual_cypher = f.read()

    actual_lines = [line.strip() for line in actual_cypher.strip().split('\n') if line.strip()]
    expected_lines = [line.strip() for line in EXPECTED_CYPHER.strip().split('\n') if line.strip()]

    assert actual_lines == expected_lines, "The generated Cypher script does not match the expected output."
    assert_index_rebuilt()


def test_script_uses_database_and_handles_a_changed_hierarchy():
    with sqlite3.connect(DB_PATH) as conn:
        conn.execute("DROP INDEX IF EXISTS idx_parent")
        conn.execute("DELETE FROM assets")
        conn.executemany(
            "INSERT INTO assets(id, name, parent_id) VALUES (?, ?, ?)",
            [
                (1, "Changed_Root", None),
                (10, "Branch_Z", 1),
                (3, "Branch_A", 1),
                (20, "Grand_Z", 10),
                (4, "Grand_A", 3),
                (30, "Depth_Three", 20),
                (31, "Too_Deep", 30),
                (2, "Orphan", 999),
                (40, "Other_Root", None),
                (41, "Other_Child", 40),
            ],
        )
        conn.commit()

    assert not os.path.exists(CYPHER_PATH) or os.path.isfile(CYPHER_PATH)
    if os.path.exists(CYPHER_PATH):
        os.remove(CYPHER_PATH)

    expected_lines = expected_from_database()
    result = subprocess.run([SCRIPT_PATH], capture_output=True, text=True)
    assert result.returncode == 0, f"Script failed on changed database. stderr: {result.stderr}"
    assert os.path.isfile(CYPHER_PATH), f"Cypher script was not generated at {CYPHER_PATH}"

    with open(CYPHER_PATH, "r", encoding="utf-8") as output_file:
        actual_lines = normalized_lines(output_file.read())

    assert actual_lines == expected_lines, (
        "Output was not derived from the current hierarchy with the depth-3 limit"
    )
    assert_index_rebuilt()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
