#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sqlite3
import random
import tempfile
import subprocess
import pytest

def generate_db(db_path, seed):
    random.seed(seed)
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    c.execute("CREATE TABLE sensors (id INTEGER, lat REAL, lon REAL, status TEXT)")
    c.execute("CREATE TABLE calibration (sensor_id INTEGER, factor REAL)")

    num_rows = random.randint(10, 100)
    for i in range(1, num_rows + 1):
        lat = random.uniform(-90, 90)
        lon = random.uniform(-180, 180)
        status = random.choice(['ACTIVE', 'INACTIVE', 'MAINTENANCE'])
        c.execute("INSERT INTO sensors VALUES (?, ?, ?, ?)", (i, lat, lon, status))

        # Skip calibration sometimes to test INNER JOIN logic
        if random.random() > 0.2:
            factor = random.uniform(0.5, 2.0)
            c.execute("INSERT INTO calibration VALUES (?, ?)", (i, factor))

    conn.commit()
    conn.close()

def test_package_installed():
    try:
        import fast_distance
        assert hasattr(fast_distance, "compute"), "fast_distance module lacks 'compute' function"
    except ImportError:
        pytest.fail("The 'fast_distance' package is not installed or failed to import. Did you fix setup.py and run pip install?")

def test_fuzz_equivalence():
    oracle_path = "/tests/oracle_pipeline.py"
    agent_path = "/home/user/pipeline.py"

    assert os.path.exists(oracle_path), f"Oracle missing at {oracle_path}"
    assert os.path.exists(agent_path), f"Agent script missing at {agent_path}"

    with tempfile.TemporaryDirectory() as tmpdir:
        for i in range(50):
            db_path = os.path.join(tmpdir, f"test_{i}.db")
            generate_db(db_path, seed=1000+i)

            oracle_res = subprocess.run(
                ["python3", oracle_path, db_path],
                capture_output=True,
                text=True
            )

            agent_res = subprocess.run(
                ["python3", agent_path, db_path],
                capture_output=True,
                text=True
            )

            assert oracle_res.returncode == 0, f"Oracle script failed on db {i}:\n{oracle_res.stderr}"
            assert agent_res.returncode == 0, f"Agent script failed on db {i}:\n{agent_res.stderr}"

            assert agent_res.stdout == oracle_res.stdout, (
                f"Output mismatch on generated database {i}.\n"
                f"Expected (Oracle):\n{oracle_res.stdout}\n"
                f"Got (Agent):\n{agent_res.stdout}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
