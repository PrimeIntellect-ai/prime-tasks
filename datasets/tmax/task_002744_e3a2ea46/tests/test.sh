#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import re
import secrets
import sqlite3
import subprocess

SCRIPT_PATH = "/home/user/analyze_risk.sh"
REPORT_PATH = "/home/user/risk_report.csv"
DB_PATH = "/home/user/financials.db"


def run_script(account):
    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)
    result = subprocess.run([SCRIPT_PATH, account], capture_output=True, text=True)
    assert result.returncode == 0, (
        f"Script failed with exit code {result.returncode}. Stderr: {result.stderr}"
    )
    assert os.path.exists(REPORT_PATH), f"Report not generated at {REPORT_PATH}"


def test_script_exists_and_executable():
    """Verify the bash script exists, is executable, and contains the required SQL constructs."""
    assert os.path.exists(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script at {SCRIPT_PATH} is not executable"

    with open(SCRIPT_PATH, "r") as f:
        content = f.read()
    assert content.startswith("#!/bin/bash"), "Script must start with #!/bin/bash"
    assert "ACC1" not in content, "The account ID must not be hardcoded in the script"
    assert re.search(r"(?is)\bWITH\s+RECURSIVE\b", content), "Query must use a recursive CTE"
    assert re.search(r"(?is)\bDENSE_RANK\s*\(", content), "Query must use DENSE_RANK()"
    assert re.search(r"(?i)\bsqlite3\b", content), "Script must query the SQLite database"
    assert re.search(r"\$(?:1|\{1\})", content), "Script must use its first argument dynamically"


def test_script_execution_and_output():
    """Run the script with ACC1 and verify the generated CSV report."""
    run_script("ACC1")

    with open(REPORT_PATH, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = [
        "rank,path,total_amount",
        "1,ACC1->ACC5->ACC6->ACC7,560.0",
        "2,ACC1->ACC2->ACC3->ACC8,550.0",
        "3,ACC1->ACC2->ACC3->ACC4,450.0"
    ]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in CSV, got {len(lines)}"
    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Mismatch at line {i+1}. Expected '{expected}', got '{actual}'"


def test_dynamic_argument_handling():
    """Run the script with a different argument to ensure it is handled dynamically."""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.executemany("INSERT INTO transfers (source, target, amount) VALUES (?, ?, ?)", [
        ('ACC99', 'ACC100', 10.0),
        ('ACC100', 'ACC101', 20.0),
        ('ACC101', 'ACC102', 30.0)
    ])
    conn.commit()
    conn.close()

    try:
        result = subprocess.run([SCRIPT_PATH, "ACC99"], capture_output=True, text=True)
        assert result.returncode == 0, f"Script failed with exit code {result.returncode} for dynamic argument."
        assert os.path.exists(REPORT_PATH), "Report not generated for ACC99"

        with open(REPORT_PATH, "r") as f:
            lines = [line.strip() for line in f.readlines() if line.strip()]

        expected_lines = [
            "rank,path,total_amount",
            "1,ACC99->ACC100->ACC101->ACC102,60.0"
        ]

        assert len(lines) == len(expected_lines), "Dynamic argument handling failed. Output does not match expected for ACC99."
        for actual, expected in zip(lines, expected_lines):
            assert actual == expected, f"Dynamic test mismatch. Expected '{expected}', got '{actual}'"
    finally:
        conn = sqlite3.connect(DB_PATH)
        conn.execute("DELETE FROM transfers WHERE source IN ('ACC99', 'ACC100', 'ACC101')")
        conn.commit()
        conn.close()


def test_randomized_graph_and_dense_ranking():
    """Exercise an unpredictable graph, including a tie that distinguishes DENSE_RANK."""
    token = secrets.token_hex(8)
    prefix = f"R_{token}_"
    start = prefix + "START"

    high = random.randint(700, 950)
    totals = [high, high, high - random.randint(30, 80), high - random.randint(120, 200)]
    edges = []
    expected = []

    for branch, total in enumerate(totals):
        n1 = prefix + f"B{branch}_1"
        n2 = prefix + f"B{branch}_2"
        n3 = prefix + f"B{branch}_3"
        first = random.randint(20, total // 3)
        second = random.randint(20, (total - first) // 2)
        third = total - first - second
        edges.extend([
            (start, n1, float(first)),
            (n1, n2, float(second)),
            (n2, n3, float(third)),
        ])
        expected.append((n1, n2, n3, total))

    # These rows are decoys of lengths other than three from the tested source.
    edges.extend([
        (start, prefix + "SHORT", 9999.0),
        (prefix + "UNRELATED", prefix + "U2", 8888.0),
        (prefix + "U2", prefix + "U3", 7777.0),
        (prefix + "U3", prefix + "U4", 6666.0),
    ])
    random.shuffle(edges)

    conn = sqlite3.connect(DB_PATH)
    conn.executemany(
        "INSERT INTO transfers (source, target, amount) VALUES (?, ?, ?)", edges
    )
    conn.commit()
    conn.close()

    try:
        run_script(start)
        with open(REPORT_PATH, newline="") as f:
            rows = list(csv.reader(f))

        assert rows and rows[0] == ["rank", "path", "total_amount"], "CSV header is incorrect"
        assert len(rows) == 5, f"Expected four exact-length paths, got {len(rows) - 1}"
        assert all(len(row) == 3 for row in rows[1:]), "Each CSV data row must have three columns"

        unique_totals = sorted(set(totals), reverse=True)
        expected_rows = set()
        for n1, n2, n3, total in expected:
            dense_rank = unique_totals.index(total) + 1
            expected_rows.add((
                str(dense_rank),
                f"{start}->{n1}->{n2}->{n3}",
                f"{float(total):.1f}",
            ))

        actual_rows = {tuple(row) for row in rows[1:]}
        assert actual_rows == expected_rows, (
            f"Randomized graph output mismatch. Expected {expected_rows}, got {actual_rows}"
        )
        ranks_in_file = [int(row[0]) for row in rows[1:]]
        assert ranks_in_file == sorted(ranks_in_file), "Results must be ordered by descending total amount"
    finally:
        conn = sqlite3.connect(DB_PATH)
        conn.execute(
            "DELETE FROM transfers WHERE source LIKE ? OR target LIKE ?",
            (prefix + "%", prefix + "%"),
        )
        conn.commit()
        conn.close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
