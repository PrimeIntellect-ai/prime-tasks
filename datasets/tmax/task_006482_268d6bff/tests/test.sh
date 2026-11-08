#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import heapq
import os
import re
import secrets
import sqlite3
import subprocess
from collections import defaultdict

HOME = "/home/user"
INIT = f"{HOME}/init_db.sh"
ANALYZE = f"{HOME}/analyze_provenance.sh"
DB = f"{HOME}/provenance.db"
SUMMARY = f"{HOME}/provenance_summary.csv"
DATASETS_CSV = f"{HOME}/datasets.csv"
DERIVATIONS_CSV = f"{HOME}/derivations.csv"

ORIGINAL_DATASETS = [
    (1, "Root Dataset", 100),
    (2, "Cleaned Data", 200),
    (3, "Filtered Data", 150),
    (4, "Aggregated Data A", 300),
    (5, "Aggregated Data B", 250),
    (6, "Final Report Data", 400),
]
ORIGINAL_EDGES = [
    (1, 2, 10), (1, 3, 15), (2, 4, 5), (3, 4, 20),
    (4, 5, 10), (3, 6, 30), (2, 6, 10), (5, 6, 5),
]
ORIGINAL_EXPECTED = (
    "depth,total_size_mb,avg_processing_time\n"
    "0,100,0.0\n"
    "1,350,12.5\n"
    "2,700,17.5\n"
    "3,250,25.0"
)


def write_fixture(datasets, edges):
    with open(DATASETS_CSV, "w", newline="") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["id", "name", "size_mb"])
        w.writerows(datasets)
    with open(DERIVATIONS_CSV, "w", newline="") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["source_id", "target_id", "processing_time_mins"])
        w.writerows(edges)


def run_script(path):
    result = subprocess.run(
        [path], cwd=HOME, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=30
    )
    assert result.returncode == 0, f"{path} failed:\n{result.stdout}"


def assert_database(datasets, edges):
    assert os.path.isfile(DB), f"Database missing: {DB}"
    conn = sqlite3.connect(DB)
    try:
        tables = {r[0] for r in conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table'"
        )}
        assert "datasets" in tables, "Table 'datasets' missing in database."
        assert "derivations" in tables, "Table 'derivations' missing in database."

        actual_datasets = conn.execute(
            "SELECT id,name,size_mb FROM datasets ORDER BY id"
        ).fetchall()
        actual_edges = conn.execute(
            "SELECT source_id,target_id,processing_time_mins "
            "FROM derivations ORDER BY source_id,target_id,processing_time_mins"
        ).fetchall()
        assert actual_datasets == sorted(datasets), "datasets.csv was not imported correctly"
        assert actual_edges == sorted(edges), "derivations.csv was not imported correctly"

        indexes = conn.execute("PRAGMA index_list('derivations')").fetchall()
        assert len(indexes) > 0, (
            "No indexes found on 'derivations' table. Expected optimal indexes "
            "for graph traversal."
        )
        leading_columns = set()
        for row in indexes:
            name = row[1].replace('"', '""')
            columns = conn.execute(f'PRAGMA index_info("{name}")').fetchall()
            if columns:
                leading_columns.add(columns[0][2])
        assert "source_id" in leading_columns, (
            "Missing an index led by derivations.source_id"
        )
        assert "target_id" in leading_columns, (
            "Missing an index led by derivations.target_id"
        )
    finally:
        conn.close()


def expected_summary(datasets, edges):
    sizes = {row[0]: row[2] for row in datasets}
    graph = defaultdict(list)
    for source, target, weight in edges:
        graph[source].append((target, weight))

    best = {1: (0, 0)}
    queue = [(0, 0, 1)]
    while queue:
        total, depth, node = heapq.heappop(queue)
        if best.get(node) != (total, depth):
            continue
        for target, weight in graph[node]:
            candidate = (total + weight, depth + 1)
            if target not in best or candidate < best[target]:
                best[target] = candidate
                heapq.heappush(queue, (candidate[0], candidate[1], target))

    grouped = defaultdict(list)
    for node, (total, depth) in best.items():
        grouped[depth].append((sizes[node], total))

    lines = ["depth,total_size_mb,avg_processing_time"]
    for depth in sorted(grouped):
        values = grouped[depth]
        total_size = sum(size for size, _ in values)
        average = sum(total for _, total in values) / len(values)
        lines.append(f"{depth},{total_size},{average:.1f}")
    return "\n".join(lines)


def run_fixture(datasets, edges, expected):
    write_fixture(datasets, edges)
    for path in (DB, SUMMARY):
        if os.path.lexists(path):
            os.remove(path)

    run_script(INIT)
    assert_database(datasets, edges)
    run_script(ANALYZE)

    assert os.path.isfile(SUMMARY), f"Output file missing: {SUMMARY}"
    with open(SUMMARY, "r", newline="") as f:
        actual = f.read().strip().replace("\r\n", "\n")
    assert actual == expected, (
        f"Content of {SUMMARY} does not match expected output.\n"
        f"Expected:\n{expected}\n\nActual:\n{actual}"
    )


def test_final_state_and_scripts():
    assert os.path.isfile(INIT), f"Script missing: {INIT}"
    assert os.access(INIT, os.X_OK), f"Script is not executable: {INIT}"
    assert os.path.isfile(ANALYZE), f"Script missing: {ANALYZE}"
    assert os.access(ANALYZE, os.X_OK), f"Script is not executable: {ANALYZE}"

    with open(ANALYZE, "r", errors="replace") as f:
        analysis_source = f.read()
    assert re.search(r"\bsqlite3\b", analysis_source), (
        "analyze_provenance.sh must use the sqlite3 command-line tool"
    )
    assert re.search(r"\bWITH\s+RECURSIVE\b", analysis_source, re.IGNORECASE), (
        "The analysis query must use a recursive CTE"
    )

    # Preserve the original fixture and its exact expected assertion, but build
    # all artifacts by executing the submitted scripts.
    run_fixture(ORIGINAL_DATASETS, ORIGINAL_EDGES, ORIGINAL_EXPECTED)

    # Exercise both scripts again on values generated only at verification time.
    r = lambda low, span: low + secrets.randbelow(span)
    datasets = [
        (1, "Dynamic Root", r(50, 80)),
        (2, "Dynamic Two", r(100, 100)),
        (3, "Dynamic Three", r(200, 100)),
        (4, "Dynamic Four", r(300, 100)),
        (5, "Dynamic Five", r(400, 100)),
        (6, "Dynamic Six", r(500, 100)),
        (7, "Dynamic Seven", r(600, 100)),
    ]
    a, b, c, d, e, f, g, h, k = [r(2, 17) for _ in range(9)]
    edges = [
        (1, 2, a), (1, 3, b),
        (2, 4, c), (3, 4, d),
        (2, 5, e), (1, 5, a + e),  # equal cost; direct path has lower depth
        (4, 6, f), (5, 6, g),
        (3, 7, h), (6, 7, k),
    ]
    run_fixture(datasets, edges, expected_summary(datasets, edges))


if __name__ == "__main__":
    test_final_state_and_scripts()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
