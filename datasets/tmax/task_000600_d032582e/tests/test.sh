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

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import sqlite3
import subprocess
from collections import Counter

import pytest
import requests

API_BASE_URL = "http://127.0.0.1:9090"
DB_PATH = "/home/user/locks.db"


def qident(name):
    return '"' + name.replace('"', '""') + '"'


def extract_video_events():
    frame = "/tmp/verifier_db_monitor.png"
    subprocess.run(
        ["ffmpeg", "-loglevel", "error", "-y", "-ss", "5.5", "-i",
         "/app/db_monitor.mp4", "-frames:v", "1", frame],
        check=True,
    )
    ocr = subprocess.run(
        ["tesseract", frame, "stdout", "--psm", "6"],
        check=True, text=True, capture_output=True,
    ).stdout

    events = set()
    for tx, action, resource in re.findall(
        r"\b(Tx\d+)\s+(ACQUIRE|WAIT)\s+(Res[A-Za-z0-9_]+)\b",
        ocr,
        flags=re.IGNORECASE,
    ):
        events.add(("Tx" + re.search(r"\d+", tx).group(), action.upper(),
                    "Res" + resource[3:]))
    assert events, f"OCR found no lock events. OCR output was: {ocr!r}"
    return events


def graph_from_events(events):
    holders = {}
    waits = []
    for tx, action, resource in events:
        if action == "ACQUIRE":
            holders.setdefault(resource.lower(), set()).add(tx)
        elif action == "WAIT":
            waits.append((tx, resource.lower()))

    edges = set()
    for waiter, resource in waits:
        for blocker in holders.get(resource, set()):
            if waiter != blocker:
                edges.add((waiter, blocker))
    return edges


def cycle_nodes_with_recursive_cte(edges):
    con = sqlite3.connect(":memory:")
    try:
        con.execute("CREATE TABLE edges(waiter TEXT, blocker TEXT)")
        con.executemany("INSERT INTO edges VALUES (?, ?)", sorted(edges))
        limit = max(1, len({x for edge in edges for x in edge}))
        rows = con.execute(
            """
            WITH RECURSIVE walk(start, node, depth) AS (
              SELECT waiter, blocker, 1 FROM edges
              UNION ALL
              SELECT walk.start, edges.blocker, walk.depth + 1
              FROM walk JOIN edges ON edges.waiter = walk.node
              WHERE walk.depth < ?
            )
            SELECT DISTINCT start FROM walk WHERE start = node ORDER BY start
            """,
            (limit,),
        ).fetchall()
        return [row[0] for row in rows]
    finally:
        con.close()


def expected_results():
    events = extract_video_events()
    edges = graph_from_events(events)
    cycle = cycle_nodes_with_recursive_cte(edges)
    indegree = Counter(blocker for waiter, blocker in edges)
    assert cycle, "No cycle could be derived from the events OCR'd from the video"
    assert indegree, "No wait-for edges could be derived from the video"
    highest = max(indegree.values())
    blocker = sorted(tx for tx, degree in indegree.items() if degree == highest)[0]
    return events, edges, ",".join(cycle), blocker


VIDEO_EVENTS, VIDEO_EDGES, VIDEO_DEADLOCK, VIDEO_BLOCKER = expected_results()


def database_events():
    con = sqlite3.connect(DB_PATH)
    try:
        assert con.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
        objects = con.execute(
            "SELECT name, type FROM sqlite_master "
            "WHERE type IN ('table','view') AND name NOT LIKE 'sqlite_%'"
        ).fetchall()
        assert objects, "locks.db contains no application tables or views"

        found = set()
        expected_txs = {tx for tx, _, _ in VIDEO_EVENTS}
        expected_resources = {resource for _, _, resource in VIDEO_EVENTS}

        for name, _ in objects:
            try:
                cur = con.execute(f"SELECT * FROM {qident(name)}")
                columns = [d[0] for d in cur.description]
                rows = cur.fetchall()
            except sqlite3.Error:
                continue

            table_context = " ".join([name] + columns).lower()
            for row in rows:
                values = ["" if value is None else str(value).strip() for value in row]
                lowered = [value.lower() for value in values]
                txs = {tx for tx in expected_txs if tx.lower() in lowered}
                resources = {r for r in expected_resources if r.lower() in lowered}
                if len(txs) != 1 or len(resources) != 1:
                    continue

                value_context = " ".join(lowered)
                if "wait" in value_context:
                    actions = {"WAIT"}
                elif "acquir" in value_context or "hold" in value_context or "owner" in value_context:
                    actions = {"ACQUIRE"}
                elif "wait" in table_context:
                    actions = {"WAIT"}
                elif any(word in table_context for word in ("acquir", "hold", "owner", "lock")):
                    actions = {"ACQUIRE"}
                else:
                    actions = set()

                for action in actions:
                    found.add((next(iter(txs)), action, next(iter(resources))))
        return found
    finally:
        con.close()


def recursive_cte_artifact_exists():
    candidates = []
    con = sqlite3.connect(DB_PATH)
    try:
        candidates.extend(
            sql for (sql,) in con.execute(
                "SELECT sql FROM sqlite_master WHERE sql IS NOT NULL"
            ).fetchall()
        )
    finally:
        con.close()

    for root in ("/home/user", "/app", "/tmp"):
        for directory, _, files in os.walk(root):
            for filename in files:
                path = os.path.join(directory, filename)
                if path in {"/tmp/test_final_state.py", DB_PATH, "/app/db_monitor.mp4"}:
                    continue
                try:
                    if not os.path.isfile(path) or os.path.getsize(path) > 2_000_000:
                        continue
                    with open(path, "r", encoding="utf-8", errors="ignore") as f:
                        candidates.append(f.read())
                except OSError:
                    pass

    return any(re.search(r"\bWITH\s+RECURSIVE\b", text, re.IGNORECASE)
               for text in candidates)


def test_sqlite_db_exists():
    """Verify that the SQLite database was created at the expected location."""
    assert os.path.isfile(DB_PATH), f"SQLite database not found at {DB_PATH}"


def test_database_contains_video_events_and_wait_for_graph():
    db_events = database_events()
    missing = VIDEO_EVENTS - db_events
    assert not missing, f"locks.db is missing video events: {sorted(missing)}"
    db_edges = graph_from_events(db_events)
    assert db_edges == VIDEO_EDGES, (
        f"Wait-for graph represented by locks.db is {sorted(db_edges)}, "
        f"expected {sorted(VIDEO_EDGES)}"
    )


def test_recursive_cte_was_written():
    assert recursive_cte_artifact_exists(), (
        "No SQL artifact containing a WITH RECURSIVE CTE was found in locks.db "
        "or the submitted files"
    )


def test_deadlock_endpoint():
    """Verify the /api/deadlock endpoint returns the correct cycle."""
    url = f"{API_BASE_URL}/api/deadlock"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to {url}: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    result = response.text.strip()
    expected = "Tx101,Tx102,Tx103"
    assert result == expected, f"Expected deadlock response '{expected}', but got '{result}'"
    assert result == VIDEO_DEADLOCK, (
        f"Deadlock response does not match the graph derived from the video: {VIDEO_DEADLOCK}"
    )


def test_blocker_endpoint():
    """Verify the /api/blocker endpoint returns the transaction with the highest blocker centrality."""
    url = f"{API_BASE_URL}/api/blocker"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to {url}: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    result = response.text.strip()
    expected = "Tx103"
    assert result == expected, f"Expected blocker response '{expected}', but got '{result}'"
    assert result == VIDEO_BLOCKER, (
        f"Blocker response does not match the graph derived from the video: {VIDEO_BLOCKER}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
