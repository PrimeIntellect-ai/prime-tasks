#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sqlite3
import subprocess
import sys

import pandas as pd
import pytest


def test_report_accuracy_and_script_execution():
    db_path = '/home/user/backups.db'
    script_path = '/home/user/analyze.py'
    report_path = '/home/user/report.csv'

    assert os.path.isfile(db_path), f"Database file {db_path} is missing."
    assert os.path.isfile(script_path), f"Analysis script {script_path} is missing."
    assert os.path.isfile(report_path), f"Agent's report file {report_path} is missing."

    # Generate golden truth from the database before re-running the artifact.
    query = """
    WITH RECURSIVE job_chain AS (
        SELECT job_id, parent_job_id, status, size_bytes, start_time
        FROM backup_jobs
        WHERE job_id = 10000
        UNION ALL
        SELECT b.job_id, b.parent_job_id, b.status, b.size_bytes, b.start_time
        FROM backup_jobs b
        INNER JOIN job_chain jc ON b.parent_job_id = jc.job_id
    ),
    cumulative AS (
        SELECT job_id, parent_job_id, status,
               SUM(size_bytes) OVER (ORDER BY start_time) AS cumulative_size
        FROM job_chain
    )
    SELECT job_id, parent_job_id, status, cumulative_size
    FROM cumulative
    WHERE status = 'FAILED'
    ORDER BY cumulative_size DESC
    LIMIT 50;
    """

    conn = sqlite3.connect(db_path)
    try:
        expected_df = pd.read_sql_query(query, conn)

        # Remove pre-existing user-created indexes so the verifier confirms that
        # analyze.py itself creates the index needed for descendant traversal.
        index_names = [
            row[0] for row in conn.execute(
                "SELECT name FROM sqlite_master "
                "WHERE type = 'index' AND name NOT LIKE 'sqlite_%'"
            ).fetchall()
        ]
        for name in index_names:
            quoted_name = name.replace('"', '""')
            conn.execute(f'DROP INDEX "{quoted_name}"')
        conn.commit()
    except Exception as exc:
        pytest.fail(f"Failed to generate golden truth or reset indexes: {exc}")
    finally:
        conn.close()

    # The submitted script must independently regenerate the report.
    os.remove(report_path)
    try:
        completed = subprocess.run(
            [sys.executable, script_path],
            cwd='/home/user',
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=120,
            check=False,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("analyze.py did not complete within 120 seconds.")

    assert completed.returncode == 0, (
        f"analyze.py exited with status {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\n"
        f"stderr:\n{completed.stderr}"
    )
    assert os.path.isfile(report_path), "analyze.py did not create /home/user/report.csv."

    # Recursive child lookup must be supported by an index whose leading column
    # is parent_job_id.
    conn = sqlite3.connect(db_path)
    try:
        parent_index_found = False
        for index_row in conn.execute("PRAGMA index_list('backup_jobs')").fetchall():
            index_name = index_row[1]
            escaped = index_name.replace("'", "''")
            columns = conn.execute(f"PRAGMA index_info('{escaped}')").fetchall()
            if columns and columns[0][2] == 'parent_job_id':
                parent_index_found = True
                break
        assert parent_index_found, (
            "analyze.py must create an index on backup_jobs with parent_job_id "
            "as its leading column."
        )
    finally:
        conn.close()

    try:
        agent_df = pd.read_csv(report_path)
    except Exception as exc:
        pytest.fail(f"Failed to read or parse the agent's report.csv: {exc}")

    required_columns = ['job_id', 'parent_job_id', 'status', 'cumulative_size']
    assert 'job_id' in agent_df.columns, "The agent's CSV must contain a 'job_id' column."
    assert list(agent_df.columns) == required_columns, (
        f"CSV headers must be exactly {required_columns}; got {list(agent_df.columns)}."
    )

    # Preserve the original job-ID Jaccard assertion.
    try:
        expected_ids = set(expected_df['job_id'].astype(int).tolist())
        agent_ids = set(agent_df['job_id'].astype(int).tolist())
    except Exception as exc:
        pytest.fail(f"The report contains invalid job_id values: {exc}")

    intersection = len(expected_ids.intersection(agent_ids))
    union = len(expected_ids.union(agent_ids))
    accuracy = intersection / union if union > 0 else 0.0
    threshold = 0.95
    assert accuracy >= threshold, (
        f"Accuracy metric failed. Calculated Jaccard similarity (accuracy): "
        f"{accuracy:.4f}, Required threshold: >= {threshold}. "
        f"Expected {len(expected_ids)} job_ids, got {len(agent_ids)} job_ids."
    )

    # Require all 50 rows and every requested value, in the requested order.
    assert len(agent_df) == 50, f"The report must contain exactly 50 rows; got {len(agent_df)}."
    try:
        pd.testing.assert_frame_equal(
            agent_df.reset_index(drop=True),
            expected_df.reset_index(drop=True),
            check_dtype=False,
            check_like=False,
        )
    except AssertionError as exc:
        pytest.fail(f"report.csv does not match the required result set: {exc}")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
