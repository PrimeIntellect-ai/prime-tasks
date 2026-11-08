#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import sqlite3
import subprocess
from pathlib import Path

DB_PATH = "/home/user/graph_backup.db"
CYPHER_PATH = "/home/user/restore.cypher"

ORIGINAL_NODES = [
    (1, "web-us-1", "US"),
    (2, "db-us-1", "US"),
    (3, "cache-us-1", "US"),
    (4, "web-us-2", "US"),
    (5, "web-eu-1", "EU"),
    (6, "db-eu-1", "EU"),
    (7, "cache-eu-1", "EU"),
]
ORIGINAL_EDGES = [
    (1, 2, 5.5),
    (1, 3, 2.1),
    (1, 4, 1.1),
    (2, 3, 1.5),
    (2, 4, 3.0),
    (4, 1, 10.0),
    (5, 6, 4.0),
    (5, 7, 3.5),
    (6, 7, 2.0),
    (7, 5, 8.0),
    (7, 6, 8.5),
]

VARIANT_NODES = [
    (11, "alpha", "X"),
    (12, "beta", "X"),
    (13, "gamma", "X"),
    (21, "delta", "Y"),
    (22, "epsilon", "Y"),
    (23, "zeta", "Y"),
    (31, "idle-a", "Z"),
    (32, "idle-b", "Z"),
]
VARIANT_EDGES = [
    (11, 12, 1.0),
    (11, 21, 2.0),
    (12, 11, 4.0),
    (21, 11, 3.0),
    (22, 21, 6.0),
    (23, 13, 7.0),
]


def expected_cypher(nodes, edges):
    stats = {node_id: [0, 0.0] for node_id, _, _ in nodes}
    for source_id, _, latency in edges:
        if source_id in stats:
            stats[source_id][0] += 1
            stats[source_id][1] += latency

    regions = {}
    for node_id, hostname, region in nodes:
        count, total = stats[node_id]
        regions.setdefault(region, []).append(
            (node_id, hostname, region, count, total)
        )

    core = []
    for servers in regions.values():
        servers.sort(key=lambda server: (-server[3], server[0]))
        core.extend(servers[:2])
    core.sort(key=lambda server: server[0])
    core_ids = {server[0] for server in core}

    lines = []
    for node_id, hostname, region, count, total in core:
        average = round(total / count, 1) if count else 0.0
        lines.append(
            f"CREATE (:Server {{id: {node_id}, hostname: '{hostname}', region: '{region}', avg_out_latency: {average}}});"
        )

    lines.append("")
    for source_id, target_id, latency in sorted(
        (edge for edge in edges if edge[0] in core_ids and edge[1] in core_ids),
        key=lambda edge: (edge[0], edge[1]),
    ):
        lines.append(
            f"MATCH (s:Server {{id: {source_id}}}), (t:Server {{id: {target_id}}}) CREATE (s)-[:CONNECTS_TO {{latency: {latency}}}]->(t);"
        )
    return "\n".join(lines)


def assert_db_matches(nodes, edges):
    conn = sqlite3.connect(DB_PATH)
    try:
        assert conn.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
        objects = conn.execute(
            "SELECT type, name, tbl_name FROM sqlite_master "
            "WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name"
        ).fetchall()
        assert objects == [
            ("table", "edges", "edges"),
            ("table", "nodes", "nodes"),
        ]
        assert conn.execute("PRAGMA table_info(nodes)").fetchall() == [
            (0, "id", "INTEGER", 0, None, 1),
            (1, "hostname", "TEXT", 0, None, 0),
            (2, "region", "TEXT", 0, None, 0),
        ]
        assert conn.execute("PRAGMA table_info(edges)").fetchall() == [
            (0, "source_id", "INTEGER", 0, None, 0),
            (1, "target_id", "INTEGER", 0, None, 0),
            (2, "latency", "REAL", 0, None, 0),
        ]
        assert conn.execute(
            "SELECT id, hostname, region FROM nodes ORDER BY id"
        ).fetchall() == sorted(nodes)
        assert conn.execute(
            "SELECT source_id, target_id, latency FROM edges ORDER BY rowid"
        ).fetchall() == edges
    finally:
        conn.close()


def create_db(nodes, edges):
    for suffix in ("", "-wal", "-shm", "-journal"):
        try:
            os.remove(DB_PATH + suffix)
        except FileNotFoundError:
            pass
    conn = sqlite3.connect(DB_PATH)
    try:
        conn.executescript(
            "CREATE TABLE nodes (id INTEGER PRIMARY KEY, hostname TEXT, region TEXT);"
            "CREATE TABLE edges (source_id INTEGER, target_id INTEGER, latency REAL);"
        )
        conn.executemany("INSERT INTO nodes VALUES (?, ?, ?)", nodes)
        conn.executemany("INSERT INTO edges VALUES (?, ?, ?)", edges)
        conn.commit()
    finally:
        conn.close()
    os.chmod(DB_PATH, 0o777)


def script_candidates():
    rank_window = re.compile(
        r"\b(?:row_number|rank|dense_rank)\s*\(\s*\)\s*over\s*\(", re.I | re.S
    )
    candidates = []
    for path in Path("/home/user").rglob("*"):
        if not path.is_file() or str(path) in {DB_PATH, CYPHER_PATH}:
            continue
        try:
            if path.stat().st_size > 1024 * 1024:
                continue
            text = path.read_text(errors="ignore")
        except OSError:
            continue
        uncommented = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
        uncommented = re.sub(r"(?m)^\s*(?:#|--).*?$", "", uncommented)
        if rank_window.search(uncommented):
            candidates.append((path, text))
    return sorted(candidates, key=lambda item: str(item[0]))


def command_for(path, text):
    suffix = path.suffix.lower()
    if suffix == ".py":
        return ["python3", str(path)], None
    if suffix in {".sh", ".bash"}:
        return ["bash", str(path)], None
    if suffix == ".sql":
        return ["sqlite3", DB_PATH], path
    first_line = text.splitlines()[0] if text.splitlines() else ""
    if "python" in first_line:
        return ["python3", str(path)], None
    if any(shell in first_line for shell in ("sh", "bash")):
        return ["bash", str(path)], None
    if os.access(path, os.X_OK):
        return [str(path)], None
    return None, None


def run_script(path, text, nodes, edges):
    create_db(nodes, edges)
    try:
        os.remove(CYPHER_PATH)
    except FileNotFoundError:
        pass

    command, stdin_path = command_for(path, text)
    if command is None:
        return False, "unrecognized script type"
    try:
        if stdin_path is None:
            result = subprocess.run(
                command, cwd="/home/user", capture_output=True, text=True, timeout=20
            )
        else:
            with open(stdin_path, "rb") as stdin_file:
                result = subprocess.run(
                    command,
                    cwd="/home/user",
                    stdin=stdin_file,
                    capture_output=True,
                    text=True,
                    timeout=20,
                )
    except (OSError, subprocess.TimeoutExpired) as exc:
        return False, str(exc)

    if result.returncode != 0:
        return False, result.stderr
    if not os.path.isfile(CYPHER_PATH):
        return False, "script did not create restore.cypher"
    try:
        assert_db_matches(nodes, edges)
        actual = Path(CYPHER_PATH).read_text()
    except (AssertionError, OSError) as exc:
        return False, str(exc)
    expected = expected_cypher(nodes, edges)
    if actual.strip() != expected.strip():
        return False, "generated Cypher did not match the exercised database"
    return True, ""


def test_database_is_original_and_unmodified():
    assert_db_matches(ORIGINAL_NODES, ORIGINAL_EDGES)


def test_restore_cypher_exists():
    assert os.path.isfile(CYPHER_PATH), f"File {CYPHER_PATH} does not exist."


def test_restore_cypher_contents():
    expected = expected_cypher(ORIGINAL_NODES, ORIGINAL_EDGES)
    actual = Path(CYPHER_PATH).read_text()
    assert actual.strip() == expected.strip(), (
        f"Contents of {CYPHER_PATH} do not match the expected output.\n"
        f"Expected:\n{expected.strip()}\n\nActual:\n{actual.strip()}"
    )


def test_script_uses_ranking_window_and_is_executable():
    original_output = Path(CYPHER_PATH).read_bytes()
    candidates = script_candidates()
    assert candidates, (
        "No Python, Bash, or SQL script containing a ranking window function "
        "(ROW_NUMBER, RANK, or DENSE_RANK with OVER) was found."
    )

    failures = []
    successful = False
    try:
        for path, text in candidates:
            ok_original, reason_original = run_script(
                path, text, ORIGINAL_NODES, ORIGINAL_EDGES
            )
            if not ok_original:
                failures.append(f"{path}: {reason_original}")
                continue
            ok_variant, reason_variant = run_script(
                path, text, VARIANT_NODES, VARIANT_EDGES
            )
            if not ok_variant:
                failures.append(f"{path}: {reason_variant}")
                continue
            successful = True
            break
    finally:
        create_db(ORIGINAL_NODES, ORIGINAL_EDGES)
        Path(CYPHER_PATH).write_bytes(original_output)

    assert successful, "No submitted script passed execution checks:\n" + "\n".join(failures)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
