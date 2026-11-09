#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import sqlite3
import subprocess
import sys
import tempfile
import shutil
import secrets
from collections import defaultdict


def expected_plan(db_path, target_db_name, target_timestamp):
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    try:
        cursor = conn.cursor()
        cursor.execute('''
            SELECT id FROM backups
            WHERE db_name = ? AND timestamp <= ?
            ORDER BY timestamp DESC, id DESC LIMIT 1
        ''', (target_db_name, target_timestamp))
        row = cursor.fetchone()
        assert row is not None, "Could not find target backup in database."
        target_id = row['id']

        cursor.execute('SELECT id, timestamp, file_path FROM backups')
        backups = {r['id']: dict(r) for r in cursor.fetchall()}
        cursor.execute('SELECT backup_id, depends_on_id FROM dependencies')
        deps = cursor.fetchall()
    finally:
        conn.close()

    adj = defaultdict(list)
    rev_adj = defaultdict(list)
    for backup_id, depends_on_id in deps:
        adj[depends_on_id].append(backup_id)
        rev_adj[backup_id].append(depends_on_id)

    required_nodes = set()
    stack = [target_id]
    while stack:
        current = stack.pop()
        if current not in required_nodes:
            required_nodes.add(current)
            stack.extend(rev_adj[current])

    in_degree = {node: 0 for node in required_nodes}
    for node in required_nodes:
        for dependency in rev_adj[node]:
            if dependency in required_nodes:
                in_degree[node] += 1

    available = [node for node in required_nodes if in_degree[node] == 0]
    result_ids = []
    while available:
        available.sort(key=lambda node: (backups[node]['timestamp'], node))
        current = available.pop(0)
        result_ids.append(current)
        for child in adj[current]:
            if child in required_nodes:
                in_degree[child] -= 1
                if in_degree[child] == 0:
                    available.append(child)

    assert len(result_ids) == len(required_nodes), "Dependency graph unexpectedly contains a cycle."
    return [backups[node]['file_path'] for node in result_ids]


def test_restore_plan_json_exists_and_correct():
    json_path = "/home/user/restore_plan.json"
    assert os.path.exists(json_path), f"File {json_path} does not exist. The script must create this file."
    assert os.path.isfile(json_path), f"{json_path} is not a file."

    db_path = "/home/user/backup_meta.db"
    assert os.path.exists(db_path), f"Database {db_path} is missing."

    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    target_db_name = "db_alpha"
    target_timestamp = 1690000050

    cursor.execute('''
        SELECT id FROM backups
        WHERE db_name = ? AND timestamp <= ?
        ORDER BY timestamp DESC, id DESC LIMIT 1
    ''', (target_db_name, target_timestamp))
    row = cursor.fetchone()
    assert row is not None, "Could not find target backup in database."
    target_id = row['id']

    cursor.execute('SELECT id, timestamp, file_path FROM backups')
    backups = {r['id']: dict(r) for r in cursor.fetchall()}

    cursor.execute('SELECT backup_id, depends_on_id FROM dependencies')
    deps = cursor.fetchall()

    adj = defaultdict(list)
    rev_adj = defaultdict(list)
    for b_id, dep_id in deps:
        adj[dep_id].append(b_id)
        rev_adj[b_id].append(dep_id)

    required_nodes = set()
    stack = [target_id]
    while stack:
        curr = stack.pop()
        if curr not in required_nodes:
            required_nodes.add(curr)
            stack.extend(rev_adj[curr])

    in_degree = {node: 0 for node in required_nodes}
    for node in required_nodes:
        for dep in rev_adj[node]:
            if dep in required_nodes:
                in_degree[node] += 1

    available = [node for node in required_nodes if in_degree[node] == 0]
    result_ids = []

    while available:
        available.sort(key=lambda x: (backups[x]['timestamp'], x))
        curr = available.pop(0)
        result_ids.append(curr)

        for child in adj[curr]:
            if child in required_nodes:
                in_degree[child] -= 1
                if in_degree[child] == 0:
                    available.append(child)

    expected_paths = [backups[node]['file_path'] for node in result_ids]
    conn.close()

    with open(json_path, 'r') as f:
        try:
            actual_paths = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{json_path} is not valid JSON."

    assert isinstance(actual_paths, list), f"Expected a JSON array in {json_path}."
    assert actual_paths == expected_paths, (
        f"Restoration plan is incorrect.\n"
        f"Expected: {expected_paths}\n"
        f"Got:      {actual_paths}"
    )


def test_script_exists():
    script_path = "/home/user/generate_plan.py"
    assert os.path.exists(script_path), f"Script {script_path} does not exist."
    assert os.path.isfile(script_path), f"{script_path} is not a file."


def test_zz_script_functionally_generates_plans():
    script_path = "/home/user/generate_plan.py"
    db_path = "/home/user/backup_meta.db"
    json_path = "/home/user/restore_plan.json"

    with tempfile.TemporaryDirectory() as temp_dir:
        saved_db = os.path.join(temp_dir, "original.db")
        shutil.copy2(db_path, saved_db)
        had_plan = os.path.exists(json_path)
        saved_plan = None
        if had_plan:
            with open(json_path, "rb") as handle:
                saved_plan = handle.read()

        try:
            if os.path.exists(db_path):
                os.remove(db_path)

            conn = sqlite3.connect(db_path)
            cursor = conn.cursor()
            cursor.execute('''
                CREATE TABLE backups (
                    id INTEGER PRIMARY KEY,
                    db_name TEXT,
                    backup_type TEXT,
                    timestamp INTEGER,
                    file_path TEXT
                )
            ''')
            cursor.execute('''
                CREATE TABLE dependencies (
                    backup_id INTEGER,
                    depends_on_id INTEGER
                )
            ''')

            ids = secrets.SystemRandom().sample(range(1000, 9000), 9)
            labels = ["root_a", "root_b", "branch_c", "branch_d", "old_target",
                      "chosen_target", "future_target", "irrelevant", "aux_future"]
            node = dict(zip(labels, ids))
            base = 1800000000 + secrets.randbelow(1000000)
            token = secrets.token_hex(12)

            rows = [
                (node["root_a"], "source_a", "FULL", base, f"/dynamic/{token}/root_a.bak"),
                (node["root_b"], "source_b", "FULL", base, f"/dynamic/{token}/root_b.bak"),
                (node["branch_c"], "aux_db", "INC", base + 10, f"/dynamic/{token}/branch_c.bak"),
                (node["branch_d"], "aux_db", "INC", base + 5, f"/dynamic/{token}/branch_d.bak"),
                (node["old_target"], "dynamic_target", "INC", base + 12, f"/dynamic/{token}/old_target.bak"),
                (node["chosen_target"], "dynamic_target", "INC", base + 20, f"/dynamic/{token}/chosen_target.bak"),
                (node["future_target"], "dynamic_target", "INC", base + 30, f"/dynamic/{token}/future_target.bak"),
                (node["irrelevant"], "unrelated_db", "FULL", base - 5, f"/dynamic/{token}/irrelevant.bak"),
                (node["aux_future"], "aux_db", "INC", base + 40, f"/dynamic/{token}/aux_future.bak"),
            ]
            dependencies = [
                (node["branch_c"], node["root_a"]),
                (node["branch_d"], node["root_b"]),
                (node["old_target"], node["root_a"]),
                (node["chosen_target"], node["branch_c"]),
                (node["chosen_target"], node["branch_d"]),
                (node["future_target"], node["chosen_target"]),
                (node["aux_future"], node["branch_c"]),
            ]
            cursor.executemany("INSERT INTO backups VALUES (?, ?, ?, ?, ?)", rows)
            cursor.executemany("INSERT INTO dependencies VALUES (?, ?)", dependencies)
            conn.commit()
            conn.close()

            cases = [
                ("dynamic_target", base + 25),
                ("dynamic_target", base + 15),
                ("aux_db", base + 15),
            ]
            for target_name, target_timestamp in cases:
                expected = expected_plan(db_path, target_name, target_timestamp)
                result = subprocess.run(
                    [sys.executable, script_path, target_name, str(target_timestamp)],
                    cwd=temp_dir,
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=15,
                )
                assert result.returncode == 0, (
                    f"Script failed for {target_name} at {target_timestamp}.\n"
                    f"stdout: {result.stdout}\nstderr: {result.stderr}"
                )
                assert os.path.isfile(json_path), "Script did not create /home/user/restore_plan.json."
                with open(json_path, "r") as handle:
                    try:
                        actual = json.load(handle)
                    except json.JSONDecodeError as exc:
                        assert False, f"Script produced invalid JSON: {exc}"
                assert isinstance(actual, list), "Script output must be a JSON array."
                assert actual == expected, (
                    f"Script generated the wrong plan for {target_name} at {target_timestamp}.\n"
                    f"Expected: {expected}\nGot: {actual}"
                )
        finally:
            if os.path.exists(db_path):
                os.remove(db_path)
            shutil.copy2(saved_db, db_path)
            if had_plan:
                with open(json_path, "wb") as handle:
                    handle.write(saved_plan)
            elif os.path.exists(json_path):
                os.remove(json_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
