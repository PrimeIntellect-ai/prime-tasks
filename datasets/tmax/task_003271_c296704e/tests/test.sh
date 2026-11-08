#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import shutil
import sqlite3
import subprocess
import time

import pytest

DB_PATH = "/app/network.db"
RESULTS_PATH = "/app/results.json"
OPTIMIZED_PATH = "/app/optimized.py"


def get_golden_results(db_path):
    """Compute the expected results based on the corrected logic."""
    conn = sqlite3.connect(db_path)
    try:
        cursor = conn.cursor()
        cursor.execute("""
            SELECT n1.region, SUM(e.weight * n2.value)
            FROM nodes n1
            JOIN edges e ON n1.id = e.source
            JOIN nodes n2 ON e.target = n2.id
            WHERE n1.type != 'bot' AND n1.value > 10
              AND n2.type != 'bot'
            GROUP BY n1.region
        """)
        return {region: total for region, total in cursor.fetchall()}
    finally:
        conn.close()


def assert_results_correct(db_path):
    assert os.path.isfile(RESULTS_PATH), "/app/results.json is missing"
    with open(RESULTS_PATH, "r") as f:
        opt_res = json.load(f)

    assert isinstance(opt_res, dict), "results.json must contain a JSON object"
    golden_res = get_golden_results(db_path)
    assert set(opt_res.keys()) == set(golden_res.keys()), \
        "The regions in results.json do not match the expected regions."

    for region, expected_val in golden_res.items():
        actual_val = opt_res[region]
        assert isinstance(actual_val, (int, float)) and not isinstance(actual_val, bool), \
            f"Value for region {region} is not numerical"
        assert math.isclose(actual_val, expected_val, rel_tol=1e-5), \
            f"Value for region {region} is incorrect. Expected ~{expected_val}, got {actual_val}"


def run_optimized(timeout=30):
    return subprocess.run(
        ["python3", OPTIMIZED_PATH],
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def create_alternate_database(path):
    """Create an unpredictable second input to reject cached or hardcoded totals."""
    rng = random.SystemRandom()
    conn = sqlite3.connect(path)
    try:
        c = conn.cursor()
        c.execute("CREATE TABLE nodes (id INTEGER PRIMARY KEY, type TEXT, region TEXT, value REAL)")
        c.execute("CREATE TABLE edges (source INTEGER, target INTEGER, weight REAL)")

        regions = ["NA", "EU", "AS"]
        types = ["user", "admin", "bot"]
        nodes = []
        for node_id in range(1, 121):
            if node_id <= 3:
                node_type = "user"
                region = regions[node_id - 1]
                value = rng.uniform(25.0, 90.0)
            else:
                node_type = rng.choice(types)
                region = rng.choice(regions)
                value = rng.uniform(1.0, 150.0)
            nodes.append((node_id, node_type, region, value))
        c.executemany("INSERT INTO nodes VALUES (?, ?, ?, ?)", nodes)

        edges = []
        # Ensure every region has qualifying paths, including bot targets that
        # must be excluded by the whiteboard constraint.
        for source in (1, 2, 3):
            edges.append((source, 4 + source, rng.uniform(0.2, 6.0)))
            bot_target = next(n[0] for n in nodes if n[1] == "bot")
            edges.append((source, bot_target, rng.uniform(0.2, 6.0)))
        for _ in range(900):
            edges.append((rng.randint(1, 120), rng.randint(1, 120), rng.uniform(0.05, 8.0)))
        c.executemany("INSERT INTO edges VALUES (?, ?, ?)", edges)
        conn.commit()
    finally:
        conn.close()


def test_optimized_script_exists():
    assert os.path.isfile(OPTIMIZED_PATH), "/app/optimized.py is missing"


def test_execution_correctness_and_performance(tmp_path):
    # Benchmark a verifier-owned copy of the supplied baseline algorithm so an
    # agent cannot inflate the baseline by editing /app/baseline.py.
    baseline_script = tmp_path / "reference_baseline.py"
    baseline_output = tmp_path / "baseline_results.json"
    baseline_script.write_text(
        "import sqlite3, json\n"
        "conn = sqlite3.connect('/app/network.db')\n"
        "c = conn.cursor()\n"
        "regions = {}\n"
        "for row in c.execute(\"SELECT id, region, value FROM nodes WHERE type != 'bot' AND value > 10\").fetchall():\n"
        "    node_id, region, val = row\n"
        "    edges = c.execute(\"SELECT target, weight FROM edges WHERE source = ?\", (node_id,)).fetchall()\n"
        "    for edge in edges:\n"
        "        target, weight = edge\n"
        "        target_val = c.execute(\"SELECT value FROM nodes WHERE id = ?\", (target,)).fetchone()[0]\n"
        "        regions[region] = regions.get(region, 0) + (weight * target_val)\n"
        f"with open({str(baseline_output)!r}, 'w') as f:\n"
        "    json.dump(regions, f)\n"
    )

    start = time.perf_counter()
    baseline_run = subprocess.run(
        ["python3", str(baseline_script)],
        capture_output=True,
        text=True,
        timeout=120,
    )
    baseline_time = time.perf_counter() - start
    assert baseline_run.returncode == 0, f"baseline failed to execute:\n{baseline_run.stderr}"

    # Remove any answer created before verification. The optimized artifact
    # itself must create the file that is checked.
    if os.path.lexists(RESULTS_PATH):
        os.remove(RESULTS_PATH)

    start = time.perf_counter()
    optimized_run = run_optimized()
    optimized_time = time.perf_counter() - start
    assert optimized_run.returncode == 0, \
        f"optimized.py failed to execute:\n{optimized_run.stderr}"

    # Validate the output produced by the timed execution, not stale state.
    assert_results_correct(DB_PATH)
    with open(RESULTS_PATH, "rb") as f:
        original_results = f.read()

    speedup = baseline_time / optimized_time if optimized_time > 0 else float("inf")
    assert speedup >= 15.0, \
        f"Speedup too low. Baseline: {baseline_time:.4f}s, Optimized: {optimized_time:.4f}s, Speedup: {speedup:.2f}x (Threshold: 15.0x)"

    # Exercise the pipeline on a verifier-generated database so merely writing
    # precomputed totals for the shipped database cannot pass.
    backup_db = tmp_path / "original_network.db"
    shutil.copy2(DB_PATH, backup_db)
    try:
        for suffix in ("", "-wal", "-shm"):
            candidate = DB_PATH + suffix
            if os.path.lexists(candidate):
                os.remove(candidate)
        create_alternate_database(DB_PATH)

        if os.path.lexists(RESULTS_PATH):
            os.remove(RESULTS_PATH)
        alternate_run = run_optimized()
        assert alternate_run.returncode == 0, \
            f"optimized.py failed on a second valid database:\n{alternate_run.stderr}"
        assert_results_correct(DB_PATH)
    finally:
        for suffix in ("", "-wal", "-shm"):
            candidate = DB_PATH + suffix
            if os.path.lexists(candidate):
                os.remove(candidate)
        shutil.copy2(backup_db, DB_PATH)
        with open(RESULTS_PATH, "wb") as f:
            f.write(original_results)


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
