#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import sqlite3
import time
import subprocess
import shutil
import pytest

def test_optimization_speedup():
    setup_script = '/home/user/setup_db.py'
    optimized_sql = '/home/user/optimized.sql'
    db_path = '/app/graph.db'
    backup_db_path = '/tmp/graph_backup.db'

    assert os.path.exists(setup_script), f"{setup_script} not found."
    assert os.path.exists(optimized_sql), f"{optimized_sql} not found."
    assert os.path.exists(db_path), f"{db_path} not found."

    # Backup the original database
    shutil.copy(db_path, backup_db_path)

    original_query = """
    SELECT a.type, SUM(e1.weight + e2.weight + e3.weight)
    FROM nodes a
    JOIN edges e1 ON a.id = e1.src
    JOIN edges e2 ON e1.dst = e2.src
    JOIN edges e3 ON e2.dst = e3.src
    WHERE a.type = 'user' AND e3.weight > 0.5
    GROUP BY a.type;
    """

    try:
        # 1. Baseline execution on the original database
        conn_base = sqlite3.connect(db_path)
        start_base = time.time()
        res_base = conn_base.execute(original_query).fetchall()
        baseline_time = time.time() - start_base
        conn_base.close()

        # 2. Apply optimizations
        result = subprocess.run(["python3", setup_script], capture_output=True, text=True)
        assert result.returncode == 0, f"setup_db.py failed with error:\n{result.stderr}"

        # 3. Read optimized query
        with open(optimized_sql, 'r') as f:
            opt_query = f.read()

        # 4. Optimized execution
        conn_opt = sqlite3.connect(db_path)
        start_opt = time.time()
        res_opt = conn_opt.execute(opt_query).fetchall()
        optimized_time = time.time() - start_opt
        conn_opt.close()

        # Validation
        assert res_base == res_opt, f"Query results do not match! Expected {res_base}, got {res_opt}"

        # Calculate speedup
        # Prevent division by zero
        if optimized_time == 0:
            optimized_time = 1e-9

        speedup = baseline_time / optimized_time
        assert speedup >= 20.0, f"Speedup {speedup:.2f} is less than required 20.0 (Baseline: {baseline_time:.4f}s, Optimized: {optimized_time:.4f}s)"

    finally:
        # Restore the original database
        shutil.copy(backup_db_path, db_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
