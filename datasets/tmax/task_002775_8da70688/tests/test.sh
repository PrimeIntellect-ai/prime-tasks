#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import csv
import os
import random
import re
import secrets
import subprocess
import sys
import tempfile
import pytest

CLEAN_DIR = "/home/user/data/clean"
EVIL_DIR = "/home/user/data/evil"
SCRIPT = "/home/user/hierarchy_validator.py"

def test_script_exists():
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} not found."

def test_clean_corpus():
    if not os.path.isdir(CLEAN_DIR):
        pytest.skip(f"Clean dir {CLEAN_DIR} missing")

    clean_files = [os.path.join(CLEAN_DIR, f) for f in os.listdir(CLEAN_DIR) if f.endswith('.csv')]
    failed = []

    for f in clean_files:
        result = subprocess.run(["python3", SCRIPT, f], capture_output=True, text=True)
        basename = os.path.basename(f)
        if result.returncode != 0 or f"CLEAN: {basename}" not in result.stdout:
            failed.append(basename)

    assert not failed, f"{len(failed)} of {len(clean_files)} clean modified/rejected: {', '.join(failed)}"

def test_evil_corpus():
    if not os.path.isdir(EVIL_DIR):
        pytest.skip(f"Evil dir {EVIL_DIR} missing")

    evil_files = [os.path.join(EVIL_DIR, f) for f in os.listdir(EVIL_DIR) if f.endswith('.csv')]
    failed = []

    for f in evil_files:
        result = subprocess.run(["python3", SCRIPT, f], capture_output=True, text=True)
        basename = os.path.basename(f)
        if result.returncode != 1 or f"EVIL: {basename}" not in result.stdout:
            failed.append(basename)

    assert not failed, f"{len(failed)} of {len(evil_files)} evil bypassed: {', '.join(failed)}"

def test_generated_hierarchies_at_same_unknown_path():
    """Exercise parsing and cycle detection without revealing the answer in the path."""
    rng = random.SystemRandom()

    with tempfile.TemporaryDirectory(prefix="hierarchy-audit-") as directory:
        basename = secrets.token_hex(12) + ".csv"
        path = os.path.join(directory, basename)
        cases = []

        for should_be_clean in (True, True, True, False, False, False):
            count = rng.randint(8, 22)
            ids = rng.sample(range(10000, 999999), count)
            parents = {ids[0]: ""}
            for index in range(1, count):
                parents[ids[index]] = ids[rng.randrange(index)]

            if not should_be_clean:
                cycle_size = rng.randint(2, min(7, count))
                cycle = rng.sample(ids, cycle_size)
                for index, employee in enumerate(cycle):
                    parents[employee] = cycle[(index + 1) % cycle_size]

            employee_column = rng.choice(["employee_id", "staff_id"])
            parent_column = rng.choice(["parent_id", "manager_id"])
            columns = [employee_column, parent_column, "display_name", "division"]
            rng.shuffle(columns)
            rows = []
            for employee in ids:
                rows.append({
                    employee_column: employee,
                    parent_column: parents[employee],
                    "display_name": "person_" + secrets.token_hex(4),
                    "division": rng.choice(["ops", "sales", "engineering"]),
                })
            rng.shuffle(rows)
            cases.append((should_be_clean, columns, rows))

        bad_schema_rows = [
            {"employee_id": rng.randint(1000, 9000), "display_name": "person_" + secrets.token_hex(4), "division": "ops"}
            for _ in range(5)
        ]
        cases.append((False, ["employee_id", "display_name", "division"], bad_schema_rows))
        rng.shuffle(cases)

        for should_be_clean, columns, rows in cases:
            with open(path, "w", newline="", encoding="utf-8") as output:
                writer = csv.DictWriter(output, fieldnames=columns)
                writer.writeheader()
                writer.writerows(rows)

            result = subprocess.run(
                ["python3", SCRIPT, path],
                capture_output=True,
                text=True,
                timeout=20,
            )
            expected_label = "CLEAN" if should_be_clean else "EVIL"
            expected_code = 0 if should_be_clean else 1
            assert result.returncode == expected_code, (
                f"Generated {expected_label} hierarchy returned {result.returncode}: "
                f"stdout={result.stdout!r}, stderr={result.stderr!r}"
            )
            assert result.stdout == f"{expected_label}: {basename}\n", (
                f"Expected exact generated-case output {expected_label}: {basename!s}; "
                f"got {result.stdout!r}"
            )

def test_required_implementation_markers():
    with open(SCRIPT, "r", encoding="utf-8") as source_file:
        source = source_file.read()
    lowered = source.lower()
    assert re.search(r"\bwith\s+recursive\b", lowered), "Validator does not contain an SQLite recursive CTE."
    assert "sqlite_utils" in lowered or "sqlite-utils" in lowered, "Validator does not use sqlite-utils."
    assert "/app/sqlite-utils-3.35" in source, "Validator does not reference the required vendored package."

def test_vendored_package_fixed():
    """Test that the sqlite-utils package bug was fixed."""
    vendored_path = "/app/sqlite-utils-3.35"
    if not os.path.isdir(vendored_path):
        pytest.fail(f"Vendored path {vendored_path} is missing.")

    sys.path.insert(0, vendored_path)
    try:
        import sqlite_utils
    except ImportError:
        pytest.fail("Failed to import sqlite_utils from vendored path.")

    db = sqlite_utils.Database(memory=True)

    # Insert rows with duplicate parent_ids
    rows = [{"id": i, "parent_id": 1} for i in range(2, 100)]
    db["hierarchy"].insert_all(rows)

    try:
        # If the bug is present, this will attempt to create a UNIQUE index and raise an IntegrityError
        db["hierarchy"].create_index(["parent_id"])
    except Exception as e:
        pytest.fail(f"Vendored package bug not fixed. Creating index failed with: {e}")

    count = db.execute("SELECT count(*) FROM hierarchy").fetchone()[0]
    assert count == 98, f"Vendored package bug not fixed: expected 98 rows, got {count}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
