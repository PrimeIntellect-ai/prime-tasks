#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import random
import sqlite3
import subprocess
import uuid

DB = "/home/user/research.db"
SCRIPT = "/home/user/extract.py"
RESULTS = "/home/user/results.json"
PLAN = "/home/user/plan.txt"

QUERY = """
SELECT
    s.id AS sample_id,
    l.name AS location_name,
    r.name AS researcher_name,
    s.collection_date,
    MAX(m.value) AS max_carbon
FROM samples s
JOIN locations l ON s.location_id = l.id
JOIN researchers r ON s.researcher_id = r.id
JOIN measurements m ON s.id = m.sample_id
WHERE s.type = 'ice_core'
  AND l.region = 'Polar'
  AND m.metric_name = 'carbon_ppm'
GROUP BY s.id, l.name, r.name, s.collection_date
ORDER BY max_carbon DESC, s.collection_date ASC
LIMIT 15 OFFSET 15
"""


def submitted_index_sql():
    if not os.path.isfile(DB):
        return []
    try:
        conn = sqlite3.connect(DB)
        rows = conn.execute(
            "SELECT sql FROM sqlite_master "
            "WHERE type='index' AND name NOT LIKE 'sqlite_%' AND sql IS NOT NULL"
        ).fetchall()
        conn.close()
        return [row[0] for row in rows]
    except sqlite3.Error:
        return []


def make_fixture(index_statements):
    if os.path.lexists(DB):
        os.remove(DB)

    rng = random.SystemRandom()
    token = uuid.uuid4().hex[:12]
    conn = sqlite3.connect(DB)
    cur = conn.cursor()
    cur.execute("CREATE TABLE locations (id INTEGER PRIMARY KEY, name TEXT, region TEXT)")
    cur.execute("CREATE TABLE researchers (id INTEGER PRIMARY KEY, name TEXT, department TEXT)")
    cur.execute("CREATE TABLE samples (id INTEGER PRIMARY KEY, location_id INTEGER, researcher_id INTEGER, collection_date TEXT, type TEXT)")
    cur.execute("CREATE TABLE measurements (id INTEGER PRIMARY KEY, sample_id INTEGER, metric_name TEXT, value REAL)")

    for i in range(1, 21):
        region = "Polar" if i <= 3 else "Region_" + str(i)
        cur.execute("INSERT INTO locations VALUES (?, ?, ?)", (i, f"Loc_{token}_{i}", region))
    for i in range(1, 12):
        cur.execute("INSERT INTO researchers VALUES (?, ?, ?)", (i, f"Res_{token}_{i}", "Climatology"))

    ranks = list(range(55))
    rng.shuffle(ranks)
    measurement_id = 1
    for sample_id in range(1, 56):
        location_id = rng.randint(1, 3)
        researcher_id = rng.randint(1, 11)
        date = f"{2000 + rng.randint(0, 20):04d}-{rng.randint(1, 12):02d}-{rng.randint(1, 28):02d}"
        cur.execute("INSERT INTO samples VALUES (?, ?, ?, ?, 'ice_core')",
                    (sample_id, location_id, researcher_id, date))
        maximum = 300.0 + ranks[sample_id - 1] * 2.0 + rng.randint(1, 99) / 1000.0
        cur.execute("INSERT INTO measurements VALUES (?, ?, 'carbon_ppm', ?)",
                    (measurement_id, sample_id, maximum - 25.0))
        measurement_id += 1
        cur.execute("INSERT INTO measurements VALUES (?, ?, 'carbon_ppm', ?)",
                    (measurement_id, sample_id, maximum))
        measurement_id += 1
        cur.execute("INSERT INTO measurements VALUES (?, ?, 'temperature', ?)",
                    (measurement_id, sample_id, 900.0 + sample_id))
        measurement_id += 1

    # Add enough nonqualifying data that full scans of the large tables are not an
    # acceptable substitute for the requested filtering/join indexes.
    for sample_id in range(56, 5056):
        if sample_id % 2:
            location_id = rng.randint(1, 3)
            sample_type = "soil"
        else:
            location_id = rng.randint(4, 20)
            sample_type = "ice_core"
        researcher_id = rng.randint(1, 11)
        date = f"{1990 + rng.randint(0, 35):04d}-{rng.randint(1, 12):02d}-{rng.randint(1, 28):02d}"
        cur.execute("INSERT INTO samples VALUES (?, ?, ?, ?, ?)",
                    (sample_id, location_id, researcher_id, date, sample_type))
        cur.execute("INSERT INTO measurements VALUES (?, ?, 'carbon_ppm', ?)",
                    (measurement_id, sample_id, rng.uniform(100.0, 800.0)))
        measurement_id += 1
        cur.execute("INSERT INTO measurements VALUES (?, ?, 'temperature', ?)",
                    (measurement_id, sample_id, rng.uniform(-80.0, 50.0)))
        measurement_id += 1

    conn.commit()
    for statement in index_statements:
        cur.execute(statement)
    conn.commit()
    conn.close()


def data_digest(conn):
    digest = hashlib.sha256()
    for table in ("locations", "researchers", "samples", "measurements"):
        for row in conn.execute(f"SELECT * FROM {table} ORDER BY id"):
            digest.update(json.dumps(row, separators=(",", ":"), ensure_ascii=False).encode())
            digest.update(b"\n")
    return digest.hexdigest()


def test_submission():
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} does not exist or is not a file."

    indexes = submitted_index_sql()
    make_fixture(indexes)

    conn = sqlite3.connect(DB)
    conn.row_factory = sqlite3.Row
    expected_rows = [dict(row) for row in conn.execute(QUERY).fetchall()]
    assert len(expected_rows) == 15, "Verifier fixture did not produce a complete second page."
    before_digest = data_digest(conn)
    conn.close()

    result = subprocess.run(["python3", SCRIPT], cwd="/home/user", capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, f"extract.py failed to execute. Error:\n{result.stderr}"

    assert os.path.exists(RESULTS), f"File {RESULTS} does not exist."
    with open(RESULTS, "r", encoding="utf-8") as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError as exc:
            raise AssertionError(f"File {RESULTS} is not valid JSON: {exc}")

    assert isinstance(results, list), "Results should be a JSON array."
    assert len(results) == 15, f"Expected exactly 15 records for page 2, found {len(results)}."

    required_keys = {"sample_id", "location_name", "researcher_name", "collection_date", "max_carbon"}
    for i, (actual, expected) in enumerate(zip(results, expected_rows)):
        assert isinstance(actual, dict), f"Record {i} is not a JSON object."
        for key in required_keys:
            assert key in actual, f"Missing '{key}' in record {i}"
        assert actual["sample_id"] == expected["sample_id"], f"Record {i} sample_id mismatch."
        assert actual["location_name"] == expected["location_name"], f"Record {i} location_name mismatch."
        assert actual["researcher_name"] == expected["researcher_name"], f"Record {i} researcher_name mismatch."
        assert actual["collection_date"] == expected["collection_date"], f"Record {i} collection_date mismatch."
        assert isinstance(actual["max_carbon"], (int, float)) and not isinstance(actual["max_carbon"], bool), f"Record {i} max_carbon is not numeric."
        assert abs(actual["max_carbon"] - expected["max_carbon"]) < 1e-5, f"Record {i} max_carbon mismatch."

    conn = sqlite3.connect(DB)
    assert data_digest(conn) == before_digest, "extract.py modified the source table data."

    index_rows = conn.execute(
        "SELECT name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%'"
    ).fetchall()
    custom_indexes = [row[0] for row in index_rows]
    assert custom_indexes, "No custom indexes found in the database. You must create indexes to optimize the query."

    actual_plan = conn.execute("EXPLAIN QUERY PLAN " + QUERY).fetchall()
    conn.close()
    details = [str(row[3]) for row in actual_plan]
    upper_details = [detail.upper() for detail in details]

    assert not any("SCAN S" in detail for detail in upper_details), "The required query performs a full scan of samples."
    assert not any("SCAN M" in detail for detail in upper_details), "The required query performs a full scan of measurements."

    used_custom = [name for name in custom_indexes if any(name in detail for detail in details)]
    assert used_custom, "The required query does not actually use any custom index."

    assert os.path.exists(PLAN), f"File {PLAN} does not exist."
    with open(PLAN, "r", encoding="utf-8") as f:
        plan_content = f.read()
    assert "USING INDEX" in plan_content or "USING COVERING INDEX" in plan_content, "Query plan does not indicate index usage."
    assert any(name in plan_content for name in used_custom), "plan.txt does not show the custom index used by the required query."

TEST_EOF

set +e
python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
set -e
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
