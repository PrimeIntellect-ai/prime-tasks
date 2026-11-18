#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sqlite3
import stat
import subprocess

DB_PATH = "/home/user/research_data.db"
SOURCE_PATH = "/home/user/analyze_graph.c"
CSV_PATH = "/home/user/summary.csv"
BINARY_PATH = "/tmp/analyze_graph_verified"


def test_program_index_and_summary():
    assert os.path.exists(DB_PATH), f"Database {DB_PATH} is missing."

    source_stat = os.lstat(SOURCE_PATH)
    assert stat.S_ISREG(source_stat.st_mode), f"{SOURCE_PATH} must be a regular C source file."

    conn = sqlite3.connect(DB_PATH)
    try:
        rows = conn.execute("""
            WITH indegrees AS (
                SELECT p.id, p.category, COUNT(c.target_id) AS degree
                FROM papers AS p
                LEFT JOIN citations AS c ON c.target_id = p.id
                GROUP BY p.id, p.category
            )
            SELECT category, id, degree
            FROM indegrees
            ORDER BY category, id
        """).fetchall()

        by_category = {}
        for category, paper_id, degree in rows:
            by_category.setdefault(category, []).append((paper_id, degree))

        expected = {}
        for category, papers in by_category.items():
            total = sum(degree for _, degree in papers)
            maximum = max(degree for _, degree in papers)
            top_ids = {paper_id for paper_id, degree in papers if degree == maximum}
            expected[category] = (total, top_ids)

        # Preserve the original fixture assertions, correcting the erroneous Math total.
        assert expected == {
            "Bio": (4, {3}),
            "CS": (5, {1}),
            "Math": (6, {6}),
        }, "The supplied citation dataset no longer has its expected contents."

        conn.execute("DROP INDEX IF EXISTS idx_target_id")
        conn.commit()
    finally:
        conn.close()

    if os.path.exists(CSV_PATH):
        os.remove(CSV_PATH)
    if os.path.exists(BINARY_PATH):
        os.remove(BINARY_PATH)

    subprocess.run(
        ["gcc", SOURCE_PATH, "-o", BINARY_PATH, "-lsqlite3"],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    subprocess.run(
        [BINARY_PATH],
        check=True,
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )

    conn = sqlite3.connect(DB_PATH)
    try:
        result = conn.execute(
            "SELECT name, tbl_name FROM sqlite_master WHERE type='index' AND name='idx_target_id'"
        ).fetchone()
        assert result is not None, "Index 'idx_target_id' was not created in the database."
        assert result[0] == "idx_target_id", "Index 'idx_target_id' was not found."
        assert result[1] == "citations", "Index 'idx_target_id' must index the citations table."

        index_columns = conn.execute("PRAGMA index_info('idx_target_id')").fetchall()
        assert index_columns, "Index 'idx_target_id' has no indexed columns."
        assert index_columns[0][2] == "target_id", (
            "Index 'idx_target_id' must have target_id as its leading indexed column."
        )
    finally:
        conn.close()

    assert os.path.exists(CSV_PATH), f"Output file {CSV_PATH} is missing."
    with open(CSV_PATH, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = [
        "Bio,4,3",
        "CS,5,1",
        "Math,6,6",
    ]
    assert len(lines) == len(expected_lines), (
        f"Expected {len(expected_lines)} lines in summary.csv, found {len(lines)}."
    )
    for expected_line, actual in zip(expected_lines, lines):
        assert actual == expected_line, f"Expected line '{expected_line}', but found '{actual}'."

    parsed = []
    for line in lines:
        fields = line.split(",")
        assert len(fields) == 3, f"Invalid summary row: {line!r}"
        category, total, top_id = fields
        parsed.append((category, int(total), int(top_id)))

    assert [row[0] for row in parsed] == sorted(expected), "Categories are not sorted alphabetically."
    for category, total, top_id in parsed:
        expected_total, allowed_top_ids = expected[category]
        assert total == expected_total
        assert top_id in allowed_top_ids
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
