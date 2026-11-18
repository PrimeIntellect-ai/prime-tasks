#!/bin/bash
set -e
mkdir -p /logs/verifier

DB_PATH=/home/user/datasets.db
REPORT_PATH=/home/user/derivation_report.csv
DB_BACKUP=$(mktemp)
REPORT_BACKUP=$(mktemp)
cp "$DB_PATH" "$DB_BACKUP"
REPORT_EXISTED=0
if [ -e "$REPORT_PATH" ]; then
    cp "$REPORT_PATH" "$REPORT_BACKUP"
    REPORT_EXISTED=1
fi
cleanup() {
    cp "$DB_BACKUP" "$DB_PATH"
    if [ "$REPORT_EXISTED" -eq 1 ]; then
        cp "$REPORT_BACKUP" "$REPORT_PATH"
    else
        rm -f "$REPORT_PATH"
    fi
    rm -f "$DB_BACKUP" "$REPORT_BACKUP"
}
trap cleanup EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import secrets
import sqlite3
import subprocess
import tomllib
from collections import defaultdict, deque

PROJECT = "/home/user/graph_analyzer"
CARGO_TOML_PATH = PROJECT + "/Cargo.toml"
MAIN_RS_PATH = PROJECT + "/src/main.rs"
DB_PATH = "/home/user/datasets.db"
CSV_PATH = "/home/user/derivation_report.csv"
HEADER = ["name", "domain", "size_mb", "path_length", "domain_rank"]


def read_csv():
    assert os.path.exists(CSV_PATH), f"CSV output missing at {CSV_PATH}"
    with open(CSV_PATH, newline="") as f:
        rows = list(csv.reader(f))
    assert rows, "CSV file is empty"
    assert rows[0] == HEADER, f"Expected header {HEADER}, got {rows[0]}"
    assert all(len(row) == 5 for row in rows[1:]), "Every data row must have five columns"
    assert rows[1:] == sorted(rows[1:], key=lambda row: row[0]), \
        "CSV rows are not sorted alphabetically by name"
    return rows[1:]


def write_fixture(datasets, edges):
    os.remove(DB_PATH)
    with sqlite3.connect(DB_PATH) as db:
        db.executescript("""
            CREATE TABLE datasets (
                id INTEGER PRIMARY KEY,
                name TEXT,
                domain TEXT,
                size_mb INTEGER
            );
            CREATE TABLE derivations (
                source_id INTEGER,
                target_id INTEGER,
                method TEXT
            );
        """)
        db.executemany("INSERT INTO datasets VALUES (?, ?, ?, ?)", datasets)
        db.executemany("INSERT INTO derivations VALUES (?, ?, ?)", edges)


def expected_rows(datasets, edges):
    by_id = {row[0]: row for row in datasets}
    roots = [row[0] for row in datasets if row[1] == "Root_Alpha"]
    assert len(roots) == 1
    root = roots[0]

    graph = defaultdict(list)
    for source, target, method in edges:
        graph[source].append((target, method))

    shortest = {root: 0}
    queue = deque([root])
    while queue:
        node = queue.popleft()
        for target, _ in graph[node]:
            if target not in shortest:
                shortest[target] = shortest[node] + 1
                queue.append(target)

    filtered = set()
    state_queue = deque([(root, False)])
    seen_states = {(root, False)}
    while state_queue:
        node, has_filter = state_queue.popleft()
        for target, method in graph[node]:
            next_flag = has_filter or method == "filter"
            state = (target, next_flag)
            if next_flag:
                filtered.add(target)
            if state not in seen_states:
                seen_states.add(state)
                state_queue.append(state)

    domain_sizes = defaultdict(set)
    for node in shortest:
        _, _, domain, size = by_id[node]
        domain_sizes[domain].add(size)
    ranks = {
        domain: {size: rank + 1 for rank, size in enumerate(sorted(sizes, reverse=True))}
        for domain, sizes in domain_sizes.items()
    }

    result = []
    for node in filtered:
        if node not in shortest:
            continue
        _, name, domain, size = by_id[node]
        result.append([
            name,
            domain,
            str(size),
            str(shortest[node]),
            str(ranks[domain][size]),
        ])
    return sorted(result, key=lambda row: row[0])


def run_program():
    if os.path.exists(CSV_PATH):
        os.remove(CSV_PATH)
    result = subprocess.run(
        ["cargo", "run", "--offline", "--quiet"],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert result.returncode == 0, \
        f"Rust program failed with exit code {result.returncode}:\n{result.stderr}"
    return read_csv()


def test_complete_graph_analyzer():
    # Preserve the original project and fixed-fixture assertions.
    assert os.path.exists(CARGO_TOML_PATH), f"Cargo.toml missing at {CARGO_TOML_PATH}"
    assert os.path.exists(MAIN_RS_PATH), f"src/main.rs missing at {MAIN_RS_PATH}"

    with open(CARGO_TOML_PATH, "r") as f:
        cargo_content = f.read()
    assert "rusqlite" in cargo_content, "rusqlite dependency not found in Cargo.toml"

    with open(CARGO_TOML_PATH, "rb") as f:
        cargo_doc = tomllib.load(f)
    dependency = cargo_doc.get("dependencies", {}).get("rusqlite")
    assert isinstance(dependency, dict), \
        "rusqlite must be configured with its version and bundled feature"
    assert str(dependency.get("version")) == "0.31.0", \
        "rusqlite version must be exactly 0.31.0"
    assert "bundled" in dependency.get("features", []), \
        "rusqlite must enable the bundled feature"

    original_rows = read_csv()
    expected_original = [
        ["Embeddings_Filtered", "ML", "1000", "4", "2"],
        ["Images_Filtered", "CV", "2000", "2", "2"],
        ["Images_Resized", "CV", "2000", "3", "2"],
    ]
    assert len(original_rows) == len(expected_original), \
        f"Expected {len(expected_original)} rows, got {len(original_rows)}"
    for expected, actual in zip(expected_original, original_rows):
        assert actual == expected, f"Expected row {expected}, got {actual}"

    # Confirm that the requested SQL and SQLite mechanisms are present in the program.
    with open(MAIN_RS_PATH, "r") as f:
        source = f.read()
    assert re.search(r"\bwith\s+recursive\b", source, re.I), \
        "The executed SQL must use a recursive CTE"
    assert re.search(r"\bdense_rank\s*\(\s*\)\s*over\b", source, re.I | re.S), \
        "The executed SQL must use DENSE_RANK as a window function"
    assert re.search(r"\bpartition\s+by\b", source, re.I), \
        "The window function must partition results"
    assert re.search(r"method\s*=\s*['\"]filter['\"]", source, re.I), \
        "The graph query must test for filter derivation edges"
    assert "/home/user/datasets.db" in source, \
        "The program must connect to /home/user/datasets.db"

    build = subprocess.run(
        ["cargo", "build", "--offline"],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert build.returncode == 0, f"Cargo build failed:\n{build.stderr}"

    suffix = secrets.token_hex(5)
    fixture_one = [
        (1, "Root_Alpha", "Core", 5101),
        (2, f"Atlas_{suffix}", "Language", 930),
        (3, f"Birch_{suffix}", "Language", 710),
        (4, f"Cedar_{suffix}", "Vision", 2400),
        (5, f"Delta_{suffix}", "Vision", 1200),
        (6, f"Echo_{suffix}", "Language", 710),
        (7, f"Hidden_{suffix}", "Vision", 9900),
    ]
    edges_one = [
        (1, 2, "clean"),
        (2, 3, "filter"),
        (1, 4, "extract"),
        (4, 5, "filter"),
        (1, 6, "clean"),
        (6, 3, "merge"),
        (7, 5, "filter"),
    ]
    write_fixture(fixture_one, edges_one)
    assert run_program() == expected_rows(fixture_one, edges_one)

    suffix = secrets.token_hex(5)
    fixture_two = [
        (11, "Root_Alpha", "Foundation", 8000),
        (12, f"Quartz_{suffix}", "Text", 4000),
        (13, f"River_{suffix}", "Text", 6000),
        (14, f"Stone_{suffix}", "Text", 4000),
        (15, f"Tiger_{suffix}", "Text", 1000),
        (16, f"Umber_{suffix}", "Media", 3300),
        (17, f"Violet_{suffix}", "Media", 3300),
        (18, f"Willow_{suffix}", "Media", 900),
        (19, f"Remote_{suffix}", "Text", 9999),
    ]
    edges_two = [
        (11, 12, "normalize"),
        (12, 13, "join"),
        (13, 14, "filter"),
        (14, 15, "summarize"),
        (11, 16, "filter"),
        (16, 17, "resize"),
        (11, 18, "copy"),
        (18, 17, "merge"),
        (19, 15, "filter"),
    ]
    write_fixture(fixture_two, edges_two)
    assert run_program() == expected_rows(fixture_two, edges_two)
TEST_EOF

set +e
python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
set -e
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
