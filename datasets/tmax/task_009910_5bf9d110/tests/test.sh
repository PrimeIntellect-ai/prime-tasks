#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import sqlite3
import stat
import subprocess
import uuid

SCRIPT_PATH = "/home/user/generate_backup_plan.sh"
PLAN_PATH = "/home/user/backup_plan.txt"
DB_PATH = "/home/user/infra_graph.db"


def read_plan():
    assert os.path.isfile(PLAN_PATH), f"Backup plan file {PLAN_PATH} does not exist."
    with open(PLAN_PATH, "r") as f:
        return [line.strip() for line in f if line.strip()]


def run_script(cluster):
    with open(PLAN_PATH, "w") as f:
        f.write("SENTINEL: this must be overwritten\n")
    result = subprocess.run(
        [SCRIPT_PATH, cluster],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"Script failed for cluster {cluster!r} with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return read_plan()


def expected_for_cluster(cluster):
    with sqlite3.connect(DB_PATH) as conn:
        rows = conn.execute(
            """
            WITH RECURSIVE descendants(id) AS (
                SELECT id FROM nodes WHERE name = ? AND type = 'cluster'
                UNION
                SELECT e.target_id
                FROM edges e
                JOIN descendants d ON e.source_id = d.id
            )
            SELECT DISTINCT n.name
            FROM descendants d
            JOIN nodes n ON n.id = d.id
            WHERE n.type = 'volume'
            ORDER BY n.name
            """,
            (cluster,),
        ).fetchall()
    return [f"[BACKUP-EXEC] Starting snapshot for volume: {name}" for (name,) in rows]


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script file {SCRIPT_PATH} does not exist."
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script file {SCRIPT_PATH} is not executable."


def test_backup_plan_contents():
    assert os.path.isfile(PLAN_PATH), f"Backup plan file {PLAN_PATH} does not exist."

    expected_lines = [
        "[BACKUP-EXEC] Starting snapshot for volume: vol-prod-data1",
        "[BACKUP-EXEC] Starting snapshot for volume: vol-prod-data2",
        "[BACKUP-EXEC] Starting snapshot for volume: vol-prod-log1",
        "[BACKUP-EXEC] Starting snapshot for volume: vol-shared-backup"
    ]

    actual_lines = read_plan()
    assert actual_lines == expected_lines, (
        f"Contents of {PLAN_PATH} do not match expected output. "
        f"Expected:\n{chr(10).join(expected_lines)}\n"
        f"Actual:\n{chr(10).join(actual_lines)}"
    )


def test_script_contains_required_query_and_pipeline():
    with open(SCRIPT_PATH, "r") as f:
        source = f.read()

    source_without_comment_lines = re.sub(r"(?m)^\s*#.*$", "", source)
    assert re.search(r"\bWITH\s+RECURSIVE\b", source_without_comment_lines, re.I), (
        "Script must use a SQLite recursive CTE."
    )
    assert re.search(r"\bsqlite3\b", source_without_comment_lines), (
        "Script must execute the query using SQLite."
    )

    parameter_match = re.search(
        r"\.parameter\s+set\s+['\"]?([:@$][A-Za-z_][A-Za-z0-9_]*)",
        source_without_comment_lines,
        re.I,
    )
    assert parameter_match, (
        "Script must bind the cluster argument with SQLite's .parameter set command."
    )
    parameter_name = parameter_match.group(1)
    assert source_without_comment_lines.count(parameter_name) >= 2, (
        "The bound SQLite parameter must be referenced by the recursive query."
    )

    pipeline_source = source_without_comment_lines.replace("||", "")
    assert re.search(r"\bsqlite3\b[\s\S]{0,2000}\|", pipeline_source), (
        "SQLite query output must be chained into a text-processing pipeline with a pipe."
    )


def test_script_executes_for_parameterized_cluster_and_overwrites_output():
    suffix = uuid.uuid4().hex
    cluster = f"verify-cluster-{suffix}"
    node = f"verify-node-{suffix}"
    volume_z = f"verify-vol-z-{suffix}"
    volume_a = f"verify-vol-a-{suffix}"
    nonvolume = f"verify-not-volume-{suffix}"
    unrelated_volume = f"verify-unrelated-{suffix}"

    inserted_ids = []
    with sqlite3.connect(DB_PATH) as conn:
        for name, node_type in [
            (cluster, "cluster"),
            (node, "node"),
            (volume_z, "volume"),
            (volume_a, "volume"),
            (nonvolume, "node"),
            (unrelated_volume, "volume"),
        ]:
            cur = conn.execute(
                "INSERT INTO nodes(name, type) VALUES (?, ?)", (name, node_type)
            )
            inserted_ids.append(cur.lastrowid)

        cluster_id, node_id, volume_z_id, volume_a_id, nonvolume_id, _ = inserted_ids
        conn.executemany(
            "INSERT INTO edges(source_id, target_id, relation) VALUES (?, ?, ?)",
            [
                (cluster_id, node_id, "contains"),
                (node_id, volume_z_id, "mounts"),
                (node_id, volume_a_id, "mounts"),
                (node_id, nonvolume_id, "contains"),
            ],
        )
        conn.commit()

    try:
        expected = expected_for_cluster(cluster)
        actual = run_script(cluster)
        assert actual == expected, (
            f"Script output for generated cluster {cluster!r} was incorrect.\n"
            f"Expected:\n{chr(10).join(expected)}\n"
            f"Actual:\n{chr(10).join(actual)}"
        )
        assert "SENTINEL: this must be overwritten" not in actual, (
            "The output file was not overwritten at the start of execution."
        )
    finally:
        with sqlite3.connect(DB_PATH) as conn:
            placeholders = ",".join("?" for _ in inserted_ids)
            conn.execute(
                f"DELETE FROM edges WHERE source_id IN ({placeholders}) OR target_id IN ({placeholders})",
                inserted_ids + inserted_ids,
            )
            conn.execute(
                f"DELETE FROM nodes WHERE id IN ({placeholders})", inserted_ids
            )
            conn.commit()
        run_script("prod-db-cluster")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
