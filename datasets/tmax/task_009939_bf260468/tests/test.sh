#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import shutil
import sqlite3
import subprocess
import tempfile

import pytest

CPP_FILE = "/home/user/process_graph.cpp"
EXE_FILE = "/home/user/process_graph"
OUTPUT_FILE = "/home/user/final_edges.csv"
DB_FILE = "/home/user/graph_data.db"
REBUILT_EXE = "/tmp/process_graph_verifier_build"


def test_cpp_file_exists():
    assert os.path.isfile(CPP_FILE), f"C++ source file {CPP_FILE} does not exist."


def test_executable_exists():
    assert os.path.isfile(EXE_FILE), f"Executable {EXE_FILE} does not exist. Did you compile the C++ program?"
    assert os.access(EXE_FILE, os.X_OK), f"File {EXE_FILE} is not executable."
    with open(EXE_FILE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{EXE_FILE} is not a compiled ELF executable."


def test_final_edges_output():
    assert os.path.isfile(OUTPUT_FILE), f"Output file {OUTPUT_FILE} does not exist."

    with open(OUTPUT_FILE, "r") as f:
        content = f.read().strip()

    assert content, f"Output file {OUTPUT_FILE} is empty."

    lines = content.split('\n')
    actual_data = []
    for line in lines:
        if not line.strip():
            continue
        parts = line.split(',')
        assert len(parts) == 3, f"Line '{line}' does not have exactly 3 comma-separated values."
        try:
            actual_data.append((float(parts[0]), float(parts[1]), float(parts[2])))
        except ValueError:
            pytest.fail(f"Could not parse line '{line}' as floats.")

    expected_data = [
        (1.0, 2.0, 12.0),
        (2.0, 3.0, 15.0),
        (4.0, 1.0, 11.0)
    ]

    assert actual_data == expected_data, f"Data in {OUTPUT_FILE} does not match expected output. Got {actual_data}, expected {expected_data}."


def _source_without_comments(text):
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    text = re.sub(r"//[^\n]*", " ", text)
    return text


def test_source_uses_one_window_query_and_binding():
    with open(CPP_FILE, "r", encoding="utf-8") as f:
        source = _source_without_comments(f.read())

    # Removing quotes lets checks span ordinary adjacent C++ SQL string literals.
    scan = source.replace('"', ' ')
    assert re.search(r"\b(row_number|rank|dense_rank|first_value|last_value|max|min)\s*\([^;]*?\)\s*over\s*\(", scan, re.I | re.S), \
        "The SQL must use a window function with an OVER clause."
    assert re.search(r"\bpartition\s+by\s+(?:[A-Za-z_]\w*\.)?source\s*,\s*(?:[A-Za-z_]\w*\.)?target\b", scan, re.I | re.S), \
        "The window must partition by source and target."
    assert re.search(r"\border\s+by\s+(?:[A-Za-z_]\w*\.)?recorded_at\s+desc\b", scan, re.I | re.S), \
        "The window must order recorded_at descending to select the latest row."
    assert re.search(r">=\s*(?:\?|[:@$][A-Za-z_]\w*)", scan, re.I), \
        "The threshold comparison must use an SQL parameter placeholder."
    assert re.search(r"\bsqlite3_bind_double\s*\(", source), \
        "The command-line double threshold must be bound with sqlite3_bind_double."

    prepares = re.findall(r"\bsqlite3_prepare_v[23]\s*\(", source)
    assert len(prepares) == 1, "The edge processing must be implemented using a single prepared SQL query."


def test_source_builds_with_sqlite():
    result = subprocess.run(
        ["g++", CPP_FILE, "-o", REBUILT_EXE, "-lsqlite3"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"process_graph.cpp did not compile with g++ -lsqlite3:\n{result.stderr}"
    assert os.path.isfile(REBUILT_EXE) and os.access(REBUILT_EXE, os.X_OK)


NUMBER = r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?"
LINE_RE = re.compile(rf"^(-?\d+),(-?\d+),({NUMBER})$")


def _run_and_parse(executable, threshold):
    result = subprocess.run(
        [executable, str(threshold)],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, \
        f"{executable} failed for threshold {threshold}: {result.stderr}"

    rows = []
    output = result.stdout.strip()
    if not output:
        return rows
    for line in output.splitlines():
        match = LINE_RE.fullmatch(line)
        assert match, f"Invalid output line from {executable}: {line!r}"
        rows.append((int(match.group(1)), int(match.group(2)), float(match.group(3))))
    return sorted(rows)


def _assert_rows(actual, expected):
    actual = sorted(actual)
    expected = sorted(expected)
    assert len(actual) == len(expected), f"Got {actual}, expected {expected}"
    for got, want in zip(actual, expected):
        assert got[:2] == want[:2], f"Got {actual}, expected {expected}"
        assert math.isclose(got[2], want[2], rel_tol=1e-9, abs_tol=1e-9), \
            f"Got {actual}, expected {expected}"


def _expected_from_rows(rows, threshold):
    latest = {}
    for source, target, weight, recorded_at in rows:
        key = (source, target)
        if key not in latest or recorded_at > latest[key][1]:
            latest[key] = (weight, recorded_at)
    return [(source, target, value[0]) for (source, target), value in latest.items()
            if value[0] >= threshold]


def test_program_execution_on_original_and_unseen_database():
    assert os.path.isfile(REBUILT_EXE), "Verifier rebuild is missing."

    # Actually exercise the requested executable on the original database and a
    # threshold different from the one used to produce final_edges.csv.
    _assert_rows(_run_and_parse(EXE_FILE, 10.5), [
        (1, 2, 12.0), (2, 3, 15.0), (4, 1, 11.0)
    ])
    _assert_rows(_run_and_parse(EXE_FILE, 12.1), [(2, 3, 15.0)])

    rows = [
        (10, 20, 99.0, 100),
        (10, 20, 6.0, 200),
        (10, 21, 7.25, 50),
        (10, 21, 8.5, 60),
        (-2, 3, 20.0, 1),
        (-2, 3, 20.5, 2),
        (7, -1, -1.0, 100),
        (7, 8, 1000.0, 1),
        (7, 8, 9.75, 4),
        (999, 1, 12.125, 300),
    ]

    backup_dir = tempfile.mkdtemp(prefix="graph_db_backup_")
    backup = os.path.join(backup_dir, "graph_data.db")
    shutil.copy2(DB_FILE, backup)
    try:
        for suffix in ("", "-wal", "-shm"):
            path = DB_FILE + suffix
            if os.path.exists(path):
                os.remove(path)
        connection = sqlite3.connect(DB_FILE)
        connection.execute("CREATE TABLE edges (id INTEGER PRIMARY KEY, source INTEGER, target INTEGER, weight REAL, recorded_at INTEGER)")
        connection.executemany(
            "INSERT INTO edges(source,target,weight,recorded_at) VALUES (?,?,?,?)", rows
        )
        connection.commit()
        connection.close()
        os.chmod(DB_FILE, 0o777)

        for threshold in (-2.0, 8.5, 10.0, 20.6):
            expected = _expected_from_rows(rows, threshold)
            _assert_rows(_run_and_parse(EXE_FILE, threshold), expected)
            _assert_rows(_run_and_parse(REBUILT_EXE, threshold), expected)
    finally:
        for suffix in ("", "-wal", "-shm"):
            path = DB_FILE + suffix
            if os.path.exists(path):
                os.remove(path)
        shutil.copy2(backup, DB_FILE)
        shutil.rmtree(backup_dir)


def test_missing_threshold_is_rejected():
    result = subprocess.run(
        [EXE_FILE], cwd="/home/user", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=10
    )
    assert result.returncode != 0, "The program must require its single threshold argument."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
