#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

# Stop any agent-started listener so the verifier executes the submitted server.py itself.
python3 - <<'PY' || true
import glob
import os
import signal
import time

inodes = set()
for table in ('/proc/net/tcp', '/proc/net/tcp6'):
    try:
        with open(table) as f:
            next(f, None)
            for line in f:
                fields = line.split()
                if len(fields) > 9 and fields[3] == '0A':
                    try:
                        port = int(fields[1].split(':')[-1], 16)
                    except ValueError:
                        continue
                    if port == 8080:
                        inodes.add(fields[9])
    except OSError:
        pass

pids = set()
for fd in glob.glob('/proc/[0-9]*/fd/*'):
    try:
        target = os.readlink(fd)
    except OSError:
        continue
    if target.startswith('socket:[') and target[8:-1] in inodes:
        try:
            pids.add(int(fd.split('/')[2]))
        except ValueError:
            pass

for pid in pids:
    if pid != os.getpid():
        try:
            os.kill(pid, signal.SIGTERM)
        except OSError:
            pass
time.sleep(0.4)
for pid in pids:
    if pid != os.getpid():
        try:
            os.kill(pid, signal.SIGKILL)
        except OSError:
            pass
PY

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib
import json
import os
import sqlite3
import subprocess
import sys
import tempfile
import time
import uuid

import pytest
import requests


def test_hyperquery_fixed():
    engine_path = "/app/hyperquery/engine.py"
    assert os.path.exists(engine_path), f"File {engine_path} does not exist."

    with open(engine_path, "r") as f:
        content = f.read()

    assert "HYPER_DB_PATHH" not in content, f"The typo 'HYPER_DB_PATHH' is still present in {engine_path}."
    assert "HYPER_DB_PATH" in content, f"'HYPER_DB_PATH' was not found in {engine_path}."

    # Exercise the package against databases and values created only at verification time.
    old_env = os.environ.get("HYPER_DB_PATH")
    paths = []
    try:
        sys.path.insert(0, "/app")
        sys.modules.pop("hyperquery.engine", None)
        import hyperquery.engine as engine
        importlib.reload(engine)

        for _ in range(2):
            fd, db_path = tempfile.mkstemp(prefix="hyperquery_verify_", suffix=".db")
            os.close(fd)
            paths.append(db_path)
            key = uuid.uuid4().hex
            value = uuid.uuid4().hex
            with sqlite3.connect(db_path) as conn:
                conn.execute("CREATE TABLE verifier_data (k TEXT PRIMARY KEY, v TEXT)")
                conn.execute("INSERT INTO verifier_data VALUES (?, ?)", (key, value))
            os.environ["HYPER_DB_PATH"] = db_path
            result = engine.execute_query(
                "SELECT v FROM verifier_data WHERE k = ?", [key]
            )
            assert result == [(value,)], (
                "hyperquery.execute_query did not read the database selected by "
                "HYPER_DB_PATH"
            )
    finally:
        if old_env is None:
            os.environ.pop("HYPER_DB_PATH", None)
        else:
            os.environ["HYPER_DB_PATH"] = old_env
        for path in paths:
            try:
                os.unlink(path)
            except OSError:
                pass


def test_optimize_sql_exists():
    sql_path = "/home/user/optimize.sql"
    assert os.path.exists(sql_path), f"File {sql_path} does not exist."
    with open(sql_path, "r") as f:
        content = f.read().lower()
    assert "create index" in content, "No CREATE INDEX statement found in optimize.sql."


def test_indexes_applied():
    db_path = "/home/user/graph_data.db"
    assert os.path.exists(db_path), f"Database {db_path} does not exist."

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    cursor.execute("SELECT name, sql FROM sqlite_master WHERE type='index';")
    indexes = cursor.fetchall()

    # Preserve the original source-level checks.
    edges_source_idx = False
    edges_target_idx = False
    nodes_json_idx = False
    for name, sql in indexes:
        if not sql:
            continue
        sql_lower = sql.lower()
        if "edges" in sql_lower and "source" in sql_lower and "rel_type" in sql_lower:
            edges_source_idx = True
        if "edges" in sql_lower and "target" in sql_lower and "rel_type" in sql_lower:
            edges_target_idx = True
        if "nodes" in sql_lower and "json_extract" in sql_lower and "category" in sql_lower:
            nodes_json_idx = True

    assert edges_source_idx, "Index on edges(source, rel_type) is missing."
    assert edges_target_idx, "Index on edges(target, rel_type) is missing."
    assert nodes_json_idx, "Index on nodes(json_extract(properties, '$.category')) is missing."

    # Validate actual key order rather than accepting keywords hidden in an unrelated definition.
    edge_index_names = [row[1] for row in cursor.execute("PRAGMA index_list('edges')")]
    source_names = []
    target_names = []
    for name in edge_index_names:
        cols = [row[2] for row in cursor.execute(
            "SELECT seqno, cid, name FROM pragma_index_info(?) ORDER BY seqno", (name,)
        )]
        if cols[:2] == ["source", "rel_type"]:
            source_names.append(name)
        if cols[:2] == ["target", "rel_type"]:
            target_names.append(name)
    assert source_names, "A real composite index beginning with edges(source, rel_type) is missing."
    assert target_names, "A real composite index beginning with edges(target, rel_type) is missing."

    # Add enough verifier-generated data for query-plan checks to demonstrate index use.
    nonce = uuid.uuid4().hex
    node_rows = []
    edge_rows = []
    for i in range(2500):
        node_rows.append((f"verify-node-{nonce}-{i}", "Item", json.dumps({"category": f"cat-{i % 101}", "n": i})))
        edge_rows.append((f"verify-source-{nonce}-{i % 113}", f"verify-target-{nonce}-{i}", f"REL-{i % 17}", "{}"))
    cursor.executemany("INSERT INTO nodes(id, labels, properties) VALUES (?, ?, ?)", node_rows)
    cursor.executemany("INSERT INTO edges(source, target, rel_type, properties) VALUES (?, ?, ?, ?)", edge_rows)
    conn.commit()
    cursor.execute("ANALYZE")

    def plan(sql, params):
        return " | ".join(row[3] for row in cursor.execute("EXPLAIN QUERY PLAN " + sql, params)).lower()

    source_plan = plan(
        "SELECT target FROM edges WHERE source = ? AND rel_type = ?",
        (f"verify-source-{nonce}-3", "REL-3"),
    )
    assert "search" in source_plan and any(name.lower() in source_plan for name in source_names), (
        f"Traversal by source and rel_type does not use the required composite index: {source_plan}"
    )

    target_plan = plan(
        "SELECT source FROM edges WHERE target = ? AND rel_type = ?",
        (f"verify-target-{nonce}-37", f"REL-{37 % 17}"),
    )
    assert "search" in target_plan and any(name.lower() in target_plan for name in target_names), (
        f"Traversal by target and rel_type does not use the required composite index: {target_plan}"
    )

    category_plan = plan(
        "SELECT id FROM nodes WHERE json_extract(properties, '$.category') = ?",
        ("cat-37",),
    )
    assert "search" in category_plan and "using index" in category_plan and "<expr>" in category_plan, (
        "Filtering on json_extract(properties, '$.category') does not use an expression index: "
        + category_plan
    )
    conn.close()


def test_server_api():
    server_path = "/home/user/server.py"
    assert os.path.isfile(server_path), f"File {server_path} does not exist."

    # Insert unpredictable records after the agent has finished, then execute its server.
    nonce = uuid.uuid4().hex
    category = "server-category-" + uuid.uuid4().hex
    source = "server-source-" + uuid.uuid4().hex
    rel_type = "SERVER_REL_" + uuid.uuid4().hex
    node_ids = ["server-node-" + uuid.uuid4().hex for _ in range(3)]
    targets = ["server-target-" + uuid.uuid4().hex for _ in range(7)]
    with sqlite3.connect("/home/user/graph_data.db") as conn:
        conn.executemany(
            "INSERT INTO nodes(id, labels, properties) VALUES (?, ?, ?)",
            [(node_id, "Verifier", json.dumps({"category": category, "nonce": nonce})) for node_id in node_ids],
        )
        conn.executemany(
            "INSERT INTO edges(source, target, rel_type, properties) VALUES (?, ?, ?, ?)",
            [(source, target, rel_type, json.dumps({"nonce": nonce})) for target in targets],
        )

    env = os.environ.copy()
    env["HYPER_DB_PATH"] = "/home/user/graph_data.db"
    log = tempfile.TemporaryFile(mode="w+")
    proc = subprocess.Popen(
        [sys.executable, server_path],
        cwd="/home/user",
        env=env,
        stdout=log,
        stderr=subprocess.STDOUT,
    )

    url = "http://127.0.0.1:8080/api/query"
    try:
        for _ in range(40):
            if proc.poll() is not None:
                log.seek(0)
                pytest.fail(f"server.py exited before testing. Output: {log.read()}")
            try:
                requests.get("http://127.0.0.1:8080/", timeout=0.25)
                break
            except requests.RequestException:
                time.sleep(0.1)
        else:
            pytest.fail("server.py did not listen on 127.0.0.1:8080")

        # Preserve all original protocol assertions.
        resp_no_auth = requests.post(url, json={"query": "SELECT 1", "params": []}, timeout=3)
        assert resp_no_auth.status_code == 401, f"Expected 401 Unauthorized without auth, got {resp_no_auth.status_code}."

        headers_bad = {"Authorization": "Bearer wrong-token"}
        resp_bad_auth = requests.post(url, json={"query": "SELECT 1", "params": []}, headers=headers_bad, timeout=3)
        assert resp_bad_auth.status_code == 401, f"Expected 401 Unauthorized with bad auth, got {resp_bad_auth.status_code}."

        headers_good = {"Authorization": "Bearer super-secret-dba-token"}
        payload = {
            "query": "SELECT target FROM edges WHERE source = ? AND rel_type = ?",
            "params": ["n2", "PURCHASED"],
        }
        resp_good = requests.post(url, json=payload, headers=headers_good, timeout=3)
        assert resp_good.status_code == 200, f"Expected 200 OK, got {resp_good.status_code}. Body: {resp_good.text}"
        try:
            data = resp_good.json()
        except ValueError:
            pytest.fail(f"Response is not valid JSON: {resp_good.text}")
        assert data == [["n1"]], f"Expected [['n1']], got {data}"

        resp_bad_json = requests.post(url, data="not a json", headers=headers_good, timeout=3)
        assert resp_bad_json.status_code == 400, f"Expected 400 Bad Request for malformed JSON, got {resp_bad_json.status_code}."
        try:
            err_data = resp_bad_json.json()
            assert err_data.get("error") == "Invalid payload", "Expected error message 'Invalid payload'."
        except ValueError:
            pass

        # Exercise several verifier-generated parameterized database reads so fixed responses fail.
        dynamic_queries = [
            (
                "SELECT id FROM nodes WHERE json_extract(properties, '$.category') = ? ORDER BY id",
                [category],
                [[x] for x in sorted(node_ids)],
            ),
            (
                "SELECT target FROM edges WHERE source = ? AND rel_type = ? ORDER BY target",
                [source, rel_type],
                [[x] for x in sorted(targets)],
            ),
            (
                "SELECT COUNT(*) FROM edges WHERE source = ? AND rel_type = ?",
                [source, rel_type],
                [[len(targets)]],
            ),
            (
                "SELECT id FROM nodes WHERE id = ?",
                [nonce + "' OR 1=1 --"],
                [],
            ),
        ]
        for query, params, expected in dynamic_queries:
            response = requests.post(
                url,
                json={"query": query, "params": params},
                headers=headers_good,
                timeout=3,
            )
            assert response.status_code == 200, response.text
            assert response.json() == expected, (
                f"Query result was not derived from the configured database. "
                f"Expected {expected}, got {response.text}"
            )

        invalid_schema = requests.post(url, json={"query": "SELECT 1"}, headers=headers_good, timeout=3)
        assert invalid_schema.status_code == 400
        assert invalid_schema.json().get("error") == "Invalid payload"
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=2)
        log.close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
