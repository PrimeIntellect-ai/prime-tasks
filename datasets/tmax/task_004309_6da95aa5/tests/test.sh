#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import sqlite3
import subprocess


def test_c_program_exists():
    """Verify that the C source and compiled executable exist."""
    assert os.path.isfile('/home/user/process.c'), "/home/user/process.c is missing."
    assert os.path.isfile('/home/user/process'), "/home/user/process executable is missing."
    assert os.access('/home/user/process', os.X_OK), "/home/user/process is not executable."


def test_pipeline_log_content():
    """Verify the pipeline.log contains the exact expected lines."""
    log_path = '/home/user/pipeline.log'
    assert os.path.isfile(log_path), f"{log_path} is missing."

    with open(log_path, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = [
        "[INFO] Starting processing",
        "[INFO] Processed 7 rows",
        "[INFO] Output written to summary.csv"
    ]

    for expected in expected_lines:
        assert expected in lines, f"Expected log line '{expected}' not found in {log_path}."


def test_summary_csv_content():
    """Verify the summary.csv contains the correct aggregated statistics."""
    csv_path = '/home/user/summary.csv'
    assert os.path.isfile(csv_path), f"{csv_path} is missing."

    with open(csv_path, 'r') as f:
        content = f.read().strip()

    expected_content = (
        "1,370.75,165,150.25\n"
        "2,390.00,155,200.00\n"
        "3,650.50,210,350.50"
    )

    assert content == expected_content, f"Content of {csv_path} does not match expected output exactly."


def test_sqlite_database():
    """Verify the analytics.db SQLite database exists and contains the correct data."""
    db_path = '/home/user/analytics.db'
    assert os.path.isfile(db_path), f"{db_path} is missing."

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='store_stats';")
    assert cursor.fetchone() is not None, "Table 'store_stats' does not exist in analytics.db."

    cursor.execute("SELECT store_id, total_revenue, total_visitors, max_revenue FROM store_stats ORDER BY store_id;")
    rows = cursor.fetchall()
    conn.close()

    expected_rows = [
        (1, 370.75, 165, 150.25),
        (2, 390.0, 155, 200.0),
        (3, 650.5, 210, 350.5)
    ]

    assert len(rows) == len(expected_rows), f"Expected {len(expected_rows)} rows in store_stats, found {len(rows)}."

    for row, expected in zip(rows, expected_rows):
        assert row[0] == expected[0], f"Expected store_id {expected[0]}, got {row[0]}."
        assert abs(row[1] - expected[1]) < 0.01, f"Expected total_revenue {expected[1]}, got {row[1]}."
        assert row[2] == expected[2], f"Expected total_visitors {expected[2]}, got {row[2]}."
        assert abs(row[3] - expected[3]) < 0.01, f"Expected max_revenue {expected[3]}, got {row[3]}."


def test_executable_and_source_process_dynamic_input():
    """Run both the submitted executable and a fresh build on unpredictable input."""
    data_path = '/home/user/data.csv'
    summary_path = '/home/user/summary.csv'
    log_path = '/home/user/pipeline.log'
    paths = [data_path, summary_path, log_path]
    saved = {}

    for path in paths:
        if os.path.exists(path):
            with open(path, 'rb') as f:
                saved[path] = f.read()
        else:
            saved[path] = None

    with open('/home/user/process', 'rb') as f:
        assert f.read(4) == b'\x7fELF', "/home/user/process is not a compiled executable."

    rebuilt = '/tmp/process_from_source'
    compile_result = subprocess.run(
        ['gcc', '/home/user/process.c', '-o', rebuilt],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20
    )
    assert compile_result.returncode == 0, f"process.c does not compile:\n{compile_result.stderr}"

    rng = random.SystemRandom()

    def run_probe(executable):
        store_ids = rng.sample(range(20, 900), 4)
        rows = []
        expected = {}
        day = 1

        for store_id in store_ids:
            expected[store_id] = {'revenue_cents': 0, 'visitors': 0, 'max_cents': -1}
            for _ in range(3):
                # Quarter-dollar amounts are exactly representable while still
                # requiring two-decimal output formatting.
                revenue_cents = rng.randint(41, 1600) * 25
                visitors = rng.randint(3, 350)
                rows.append((f'2026-08-{day:02d}', store_id, revenue_cents, visitors))
                day += 1
                expected[store_id]['revenue_cents'] += revenue_cents
                expected[store_id]['visitors'] += visitors
                expected[store_id]['max_cents'] = max(expected[store_id]['max_cents'], revenue_cents)

        rng.shuffle(rows)
        with open(data_path, 'w') as f:
            f.write('date,store_id,revenue,visitors\n')
            for date, store_id, cents, visitors in rows:
                f.write(f'{date},{store_id},{cents // 100}.{cents % 100:02d},{visitors}\n')

        for path in (summary_path, log_path):
            if os.path.exists(path):
                os.remove(path)

        result = subprocess.run(
            [executable],
            cwd='/home/user',
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10
        )
        assert result.returncode == 0, f"{executable} failed on probe input: {result.stderr}"
        assert os.path.isfile(summary_path), f"{executable} did not create summary.csv"
        assert os.path.isfile(log_path), f"{executable} did not create pipeline.log"

        expected_lines = []
        for store_id in sorted(expected):
            values = expected[store_id]
            total = values['revenue_cents']
            maximum = values['max_cents']
            expected_lines.append(
                f"{store_id},{total // 100}.{total % 100:02d},{values['visitors']},"
                f"{maximum // 100}.{maximum % 100:02d}"
            )

        with open(summary_path, 'r') as f:
            actual_summary = f.read().strip()
        assert actual_summary == '\n'.join(expected_lines), (
            f"{executable} did not aggregate the probe data correctly."
        )

        with open(log_path, 'r') as f:
            actual_log = f.read().splitlines()
        assert actual_log == [
            '[INFO] Starting processing',
            f'[INFO] Processed {len(rows)} rows',
            '[INFO] Output written to summary.csv'
        ], f"{executable} did not append the required three log lines for the probe run."

    try:
        run_probe('/home/user/process')
        run_probe(rebuilt)
    finally:
        for path, content in saved.items():
            if content is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                with open(path, 'wb') as f:
                    f.write(content)
        if os.path.exists(rebuilt):
            os.remove(rebuilt)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
