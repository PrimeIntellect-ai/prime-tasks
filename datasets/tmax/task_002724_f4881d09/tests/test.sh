#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import secrets
import sqlite3
import subprocess
import time

AGENT_SCRIPT = "/home/user/optimized_flow.py"
ORACLE_BINARY = "/app/legacy_flow_calc"
DATABASE = "/home/user/topology.db"

# Verify the oracle was present for the analysis phase, then create an
# unpredictable equivalent database so fixed answers cannot pass.
assert os.path.exists(ORACLE_BINARY), f"Oracle binary {ORACLE_BINARY} is missing."
ORACLE_WAS_AVAILABLE = True

rng = random.Random(secrets.randbits(256))
conn = sqlite3.connect(DATABASE)
conn.executescript("DROP TABLE IF EXISTS edges; DROP TABLE IF EXISTS nodes;")
conn.execute("CREATE TABLE nodes (id INTEGER PRIMARY KEY, name TEXT, base_weight REAL)")
conn.execute("CREATE TABLE edges (source_id INTEGER, target_id INTEGER, latency REAL)")
conn.executemany(
    "INSERT INTO nodes VALUES (?, ?, ?)",
    ((i, f"Verification_Node_{i}", rng.uniform(1.0, 100.0)) for i in range(1, 10001)),
)
# A long hierarchy makes the legacy N+1 implementation measurably slower,
# while the remaining nodes provide additional valid roots.
edges = [(i, i + 1, rng.uniform(0.1, 10.0)) for i in range(1, 4000)]
edges.extend((i, 10000, rng.uniform(0.1, 10.0)) for i in range(4001, 10000))
conn.executemany("INSERT INTO edges VALUES (?, ?, ?)", edges)
conn.commit()
conn.close()

stress_root = rng.randint(1, 25)

def run_oracle(node_id):
    start = time.monotonic()
    result = subprocess.run(
        [ORACLE_BINARY, str(node_id)],
        capture_output=True,
        text=True,
        check=True,
        timeout=30,
    )
    return result.stdout.strip(), time.monotonic() - start

# Use the real implementation to retain the original equivalence assertion and
# to establish a machine-local performance baseline. The second run is warm.
legacy_output_1, legacy_time_1 = run_oracle(stress_root)
legacy_output_2, legacy_time_2 = run_oracle(stress_root)
assert legacy_output_1 == legacy_output_2
legacy_time = min(legacy_time_1, legacy_time_2)

# Derive secret fuzz answers independently with the required set-based metric.
def expected_output(node_id):
    db = sqlite3.connect(DATABASE)
    try:
        row = db.execute(
            """
            WITH RECURSIVE walk(node_id, path_latency) AS (
                SELECT target_id, latency
                FROM edges
                WHERE source_id = ?
                UNION ALL
                SELECT e.target_id, walk.path_latency + e.latency
                FROM walk
                JOIN edges AS e ON e.source_id = walk.node_id
            )
            SELECT printf('%.4f', COALESCE(SUM(n.base_weight / walk.path_latency), 0.0))
            FROM walk
            JOIN nodes AS n ON n.id = walk.node_id
            """,
            (node_id,),
        ).fetchone()
        return row[0]
    finally:
        db.close()

assert expected_output(stress_root) == legacy_output_1
case_ids = [rng.randint(1, 10000) for _ in range(100)]
case_ids[0] = stress_root
expected_cases = [(node_id, expected_output(node_id)) for node_id in case_ids]

# The artifact remains available while the agent works, as instructed, but is
# unavailable to the submitted program during verification.
os.unlink(ORACLE_BINARY)


def run_agent(node_id, timeout=3):
    return subprocess.run(
        ["python3", AGENT_SCRIPT, str(node_id)],
        capture_output=True,
        text=True,
        check=True,
        timeout=timeout,
    ).stdout.strip()


def test_agent_script_exists():
    assert os.path.exists(AGENT_SCRIPT), f"Agent script {AGENT_SCRIPT} is missing."
    assert os.path.isfile(AGENT_SCRIPT), f"{AGENT_SCRIPT} is not a file."


def test_uses_parameterized_recursive_sql():
    source = open(AGENT_SCRIPT, "r", encoding="utf-8").read()
    assert re.search(r"\bWITH\s+RECURSIVE\b", source, re.IGNORECASE), \
        "The implementation must perform traversal with a recursive CTE."
    assert "sqlite3" in source, "The implementation must query SQLite directly."
    assert re.search(r"\?|[:@$][A-Za-z_]\w*", source), \
        "The SQL must use a parameter placeholder for the root node."
    assert "legacy_flow_calc" not in source, \
        "The replacement must not invoke the legacy executable."


def test_oracle_was_available_for_analysis():
    assert ORACLE_WAS_AVAILABLE


def test_fuzz_equivalence():
    for node_id, expected in expected_cases:
        try:
            actual = run_agent(node_id)
        except subprocess.TimeoutExpired:
            raise AssertionError(f"Agent script timed out on node ID {node_id}.")
        except subprocess.CalledProcessError as exc:
            raise AssertionError(
                f"Agent script failed on node ID {node_id}: {exc.stderr}"
            )
        assert actual == expected, (
            f"Mismatch on node ID {node_id}.\n"
            f"Expected output: {expected}\n"
            f"Agent output:    {actual}"
        )


def test_significantly_faster_than_legacy():
    # Allow Python startup overhead while requiring a substantial improvement
    # over the warmed legacy implementation on the same database and root.
    limit = max(0.06, legacy_time * 0.45)
    start = time.monotonic()
    try:
        actual = run_agent(stress_root, timeout=max(2.0, limit * 3.0))
    except subprocess.TimeoutExpired:
        raise AssertionError("Agent script timed out on the optimization case.")
    elapsed = time.monotonic() - start
    assert actual == legacy_output_1
    assert elapsed < limit, (
        f"Implementation is not significantly faster than the legacy tool: "
        f"agent={elapsed:.3f}s, legacy={legacy_time:.3f}s, limit={limit:.3f}s"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
