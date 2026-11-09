#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import filecmp
import os
import random
import re
import shutil
import sqlite3
import subprocess
import tempfile

import cv2

DB_PATH = "/home/user/graph.db"
QUERY_BIN = "/home/user/query"
QUERY_SRC = "/home/user/query.c"


def decode_video():
    cap = cv2.VideoCapture("/app/graph.mp4")
    assert cap.isOpened(), "Could not open /app/graph.mp4"
    rows = []
    frame_no = 1
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        pixel = cv2.resize(frame, (1, 1))[0, 0]
        b, g, r = (int(x) for x in pixel)
        rows.append((frame_no, r, g, b))
        frame_no += 1
    cap.release()
    assert rows, "Video contained no decodable frames"
    return rows


def test_database_exists_and_contents():
    assert os.path.exists(DB_PATH), f"Database file is missing: {DB_PATH}"
    assert os.path.isfile(DB_PATH), f"Expected a file at {DB_PATH}"

    expected = decode_video()
    uri = "file:" + DB_PATH + "?mode=ro"
    con = sqlite3.connect(uri, uri=True)
    try:
        table_info = con.execute("PRAGMA table_info(edges)").fetchall()
        assert table_info, "Missing edges table"
        actual_columns = [(row[1], row[2].upper()) for row in table_info]
        assert actual_columns == [
            ("frame", "INTEGER"),
            ("src", "INTEGER"),
            ("dst", "INTEGER"),
            ("weight", "INTEGER"),
        ], f"Incorrect edges schema: {actual_columns}"

        actual = con.execute(
            "SELECT frame, src, dst, weight FROM edges ORDER BY frame"
        ).fetchall()
        assert actual == expected, "edges does not exactly match the decoded video"

        indexes = con.execute("PRAGMA index_list(edges)").fetchall()
        indexed_columns = []
        for index_row in indexes:
            name = index_row[1]
            cols = [r[2] for r in con.execute(
                'PRAGMA index_info("' + name.replace('"', '""') + '")'
            ).fetchall()]
            indexed_columns.append(cols)
        assert any(cols[:2] == ["src", "frame"] for cols in indexed_columns), (
            "edges needs a composite index beginning with (src, frame) for the "
            "recursive temporal expansion"
        )
    finally:
        con.close()


def test_query_artifacts_and_source_requirements():
    assert os.path.exists(QUERY_BIN), f"Compiled binary is missing: {QUERY_BIN}"
    assert os.path.isfile(QUERY_BIN), f"Expected a file at {QUERY_BIN}"
    assert os.access(QUERY_BIN, os.X_OK), f"Binary is not executable: {QUERY_BIN}"
    with open(QUERY_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", "query must be a compiled ELF executable"

    assert os.path.isfile(QUERY_SRC), f"C source is missing: {QUERY_SRC}"
    with open(QUERY_SRC, "r", encoding="utf-8", errors="replace") as f:
        source = f.read()

    assert re.search(r"\bWITH\s+RECURSIVE\b", source, re.I), (
        "query.c must contain a recursive CTE"
    )
    assert "sqlite3_prepare" in source, "query.c must prepare its SQL statement"
    assert len(re.findall(r"sqlite3_bind_(?:int|int64)\s*\(", source)) >= 2, (
        "query.c must bind both node parameters"
    )
    assert source.count("?") >= 2, "The SQL must contain parameter placeholders"

    if os.path.isfile("/app/oracle_query.c"):
        assert not filecmp.cmp(QUERY_SRC, "/app/oracle_query.c", shallow=False), (
            "query.c must not be byte-identical to the reference implementation"
        )
    if os.path.isfile("/app/oracle_query"):
        assert not filecmp.cmp(QUERY_BIN, "/app/oracle_query", shallow=False), (
            "query must not be byte-identical to the reference executable"
        )


def optimal_path(edges, start, end):
    # As frames are processed in order, best[node] is the cheapest path that has
    # arrived at node so far. Earlier consequences of a superseded path have
    # already been propagated to their later edges.
    best = {}
    for frame, src, dst, weight in edges:
        candidates = []
        if src == start:
            candidates.append((weight, frame, (frame,)))
        previous = best.get(src)
        if previous is not None:
            candidates.append((
                previous[0] + weight,
                frame,
                previous[2] + (frame,),
            ))
        for candidate in candidates:
            current = best.get(dst)
            if current is None or candidate[:2] < current[:2]:
                best[dst] = candidate
    return best.get(end)


def validate_output(stdout, edges, start, end, expected):
    if expected is None:
        assert stdout == "No path\n", (
            f"Expected No path for {start}->{end}, got {stdout!r}"
        )
        return

    match = re.fullmatch(r"Weight: (\d+), Frames: (\d+(?:,\d+)*)\n", stdout)
    assert match, f"Output has the wrong format for {start}->{end}: {stdout!r}"
    reported_weight = int(match.group(1))
    frames = tuple(int(x) for x in match.group(2).split(","))
    assert all(a < b for a, b in zip(frames, frames[1:])), (
        "Path frames are not strictly increasing"
    )

    by_frame = {row[0]: row for row in edges}
    node = start
    actual_weight = 0
    for frame in frames:
        assert frame in by_frame, f"Reported nonexistent frame {frame}"
        _, src, dst, weight = by_frame[frame]
        assert src == node, f"Frame {frame} does not continue the reported path"
        node = dst
        actual_weight += weight
    assert node == end, f"Reported path ends at {node}, not {end}"
    assert actual_weight == reported_weight, "Reported weight does not match its frames"
    assert (reported_weight, frames[-1]) == expected[:2], (
        f"Path is not optimal for {start}->{end}: expected score/arrival "
        f"{expected[:2]}, got {(reported_weight, frames[-1])}"
    )


def make_synthetic_edges():
    rng = random.Random(9173)
    edges = [
        (1, 0, 1, 9),
        (2, 0, 2, 2),
        (3, 2, 1, 2),
        (4, 1, 3, 4),
        (5, 2, 3, 20),
        (6, 3, 4, 1),
        (7, 0, 4, 30),
        (8, 4, 0, 3),
        (9, 1, 5, 5),
        (10, 5, 4, 1),
    ]
    for frame in range(11, 41):
        src = rng.randrange(9)
        dst = rng.randrange(9)
        weight = rng.randrange(1, 16)
        edges.append((frame, src, dst, weight))
    return edges


def install_synthetic_db(edges):
    for suffix in ("", "-wal", "-shm"):
        try:
            os.remove(DB_PATH + suffix)
        except FileNotFoundError:
            pass
    con = sqlite3.connect(DB_PATH)
    try:
        con.execute("CREATE TABLE edges(frame INTEGER, src INTEGER, dst INTEGER, weight INTEGER)")
        con.executemany("INSERT INTO edges VALUES (?, ?, ?, ?)", edges)
        con.execute("CREATE INDEX edges_src_frame ON edges(src, frame)")
        con.commit()
    finally:
        con.close()


def exercise_binary(binary, edges, queries):
    for args in ([], ["1"], ["1", "2", "3"]):
        result = subprocess.run([binary] + args, capture_output=True, text=True, timeout=2)
        assert result.returncode != 0, f"{binary} must accept exactly two arguments"

    for start, end in queries:
        expected = optimal_path(edges, start, end)
        result = subprocess.run(
            [binary, str(start), str(end)],
            capture_output=True,
            text=True,
            timeout=2,
        )
        assert result.returncode == 0, (
            f"Nonzero return code for {start}->{end}: {result.returncode}; "
            f"stderr={result.stderr!r}"
        )
        assert result.stderr == "", f"Unexpected stderr: {result.stderr!r}"
        validate_output(result.stdout, edges, start, end, expected)


def test_independent_fuzz_and_compiled_source():
    build_dir = tempfile.mkdtemp(prefix="query-build-")
    rebuilt = os.path.join(build_dir, "query")
    build = subprocess.run(
        ["gcc", "-O2", QUERY_SRC, "-o", rebuilt, "-lsqlite3"],
        capture_output=True,
        text=True,
    )
    assert build.returncode == 0, f"query.c does not compile:\n{build.stderr}"

    backup = os.path.join(build_dir, "original-graph.db")
    shutil.copy2(DB_PATH, backup)
    edges = make_synthetic_edges()
    rng = random.Random(42)
    queries = [(rng.randint(0, 15), rng.randint(0, 15)) for _ in range(90)]
    queries += [(0, 4), (0, 3), (0, 5), (4, 4), (8, 0),
                (7, 2), (2, 4), (1, 4), (5, 0), (0, 8)]

    try:
        for binary in (QUERY_BIN, rebuilt):
            install_synthetic_db(edges)
            exercise_binary(binary, edges, queries)
    finally:
        for suffix in ("", "-wal", "-shm"):
            try:
                os.remove(DB_PATH + suffix)
            except FileNotFoundError:
                pass
        shutil.copy2(backup, DB_PATH)
        shutil.rmtree(build_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
