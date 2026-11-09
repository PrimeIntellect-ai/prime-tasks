#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import shutil
import sqlite3
import subprocess

import jsonschema
import pytest

PROCESS_PATH = "/home/user/process.py"
RESULTS_PATH = "/home/user/results.json"
DB_PATH = "/home/user/papers.db"
SCHEMA_PATH = "/home/user/schema.json"


def run_process():
    return subprocess.run(
        ["python3", PROCESS_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )


def load_results():
    assert os.path.isfile(RESULTS_PATH), f"Expected output file not found: {RESULTS_PATH}"
    with open(RESULTS_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{RESULTS_PATH} does not contain valid JSON.")


def derive_expected(db_path):
    conn = sqlite3.connect(db_path)
    try:
        papers = conn.execute("SELECT id, title, year FROM papers").fetchall()
        counts = {
            paper_id: conn.execute(
                "SELECT COUNT(*) FROM citations WHERE cited_id = ?", (paper_id,)
            ).fetchone()[0]
            for paper_id, _, _ in papers
        }

        winners = {}
        for paper_id, title, year in papers:
            candidate = (paper_id, title, year, counts[paper_id])
            current = winners.get(year)
            if current is None or (-candidate[3], candidate[0]) < (-current[3], current[0]):
                winners[year] = candidate

        selected = sorted(winners.values(), key=lambda row: -row[2])[:2]
        expected = []
        for paper_id, title, year, count in selected:
            indirect = [
                row[0]
                for row in conn.execute(
                    """
                    SELECT c.title
                    FROM citations first_edge
                    JOIN citations second_edge
                      ON second_edge.cited_id = first_edge.citing_id
                    JOIN papers c ON c.id = second_edge.citing_id
                    WHERE first_edge.cited_id = ?
                    ORDER BY c.title ASC
                    """,
                    (paper_id,),
                ).fetchall()
            ]
            expected.append({
                "id": paper_id,
                "title": title,
                "year": year,
                "total_citations": count,
                "indirect_citations": indirect,
            })
        return expected
    finally:
        conn.close()


def test_process_script_exists_uses_required_tools_and_runs():
    assert os.path.isfile(PROCESS_PATH), f"Expected script not found: {PROCESS_PATH}"
    assert not os.path.islink(PROCESS_PATH), f"{PROCESS_PATH} must be a real script file"

    with open(PROCESS_PATH, "r") as f:
        source = f.read()
    compile(source, PROCESS_PATH, "exec")

    assert re.search(
        r"(?is)\b(?:row_number|rank|dense_rank)\s*\([^)]*\)\s*over\s*\(", source
    ), "process.py must use a SQL window ranking function with OVER"
    assert re.search(
        r"(?m)^\s*(?:import\s+jsonschema\b|from\s+jsonschema\s+import\b)", source
    ), "process.py must import the jsonschema library"

    if os.path.exists(RESULTS_PATH):
        os.remove(RESULTS_PATH)
    completed = run_process()
    assert completed.returncode == 0, (
        f"process.py failed:\nstdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )


def test_results_json_exists_and_correct():
    data = load_results()

    expected_data = [
        {
            "id": 5,
            "title": "CitesRoot2_A",
            "year": 2022,
            "total_citations": 0,
            "indirect_citations": []
        },
        {
            "id": 4,
            "title": "Root2",
            "year": 2021,
            "total_citations": 3,
            "indirect_citations": []
        }
    ]

    assert data == expected_data, f"The contents of {RESULTS_PATH} do not match the expected output."
    with open(SCHEMA_PATH, "r") as f:
        jsonschema.validate(data, json.load(f))


def test_results_json_formatting():
    assert os.path.isfile(RESULTS_PATH), f"Expected output file not found: {RESULTS_PATH}"
    with open(RESULTS_PATH, "r") as f:
        content = f.read()
    assert "\n  {" in content or "\n  \"" in content, \
        "The JSON file does not appear to be formatted with 2-space indentation as required."


def test_process_handles_derived_database_and_enforces_schema(tmp_path):
    db_backup = tmp_path / "papers.db"
    schema_backup = tmp_path / "schema.json"
    shutil.copy2(DB_PATH, db_backup)
    shutil.copy2(SCHEMA_PATH, schema_backup)

    try:
        os.remove(DB_PATH)
        conn = sqlite3.connect(DB_PATH)
        conn.executescript("""
            CREATE TABLE papers (id INTEGER PRIMARY KEY, title TEXT, year INTEGER);
            CREATE TABLE citations (citing_id INTEGER, cited_id INTEGER);
            INSERT INTO papers VALUES
                (14, 'Target', 2031),
                (16, 'Other 2031', 2031),
                (15, 'Direct B', 2032),
                (18, 'Hop B', 2032),
                (19, 'Hop C', 2028),
                (20, 'Older', 2030);
            INSERT INTO citations VALUES
                (15, 14),
                (18, 15),
                (19, 18);
        """)
        conn.commit()
        conn.close()

        expected = derive_expected(DB_PATH)
        if os.path.exists(RESULTS_PATH):
            os.remove(RESULTS_PATH)
        completed = run_process()
        assert completed.returncode == 0, (
            f"process.py failed on another valid database:\n{completed.stderr}"
        )
        assert load_results() == expected

        with open(SCHEMA_PATH, "w") as f:
            json.dump({"type": "array", "maxItems": 0}, f)
        if os.path.exists(RESULTS_PATH):
            os.remove(RESULTS_PATH)
        run_process()
        assert not os.path.exists(RESULTS_PATH), \
            "process.py wrote results even though jsonschema validation should fail"
    finally:
        shutil.copy2(db_backup, DB_PATH)
        shutil.copy2(schema_backup, SCHEMA_PATH)
        if os.path.exists(RESULTS_PATH):
            os.remove(RESULTS_PATH)
        run_process()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
