#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import sqlite3
import subprocess
import pytest

OUTPUT_PATH = '/home/user/output/top_modules_graph.json'
DB_PATH = '/home/user/data/legacy_system.db'
SCRIPT_PATH = '/home/user/etl_pipeline.py'

def test_output_file_exists():
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} does not exist."

def test_json_structure_and_metadata():
    with open(OUTPUT_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Output file is not valid JSON.")

    assert "page" in data, "Missing 'page' in JSON."
    assert "limit" in data, "Missing 'limit' in JSON."
    assert "total_active_modules" in data, "Missing 'total_active_modules' in JSON."
    assert "results" in data, "Missing 'results' in JSON."

    assert data["page"] == 1, f"Expected page 1, got {data['page']}"
    assert data["limit"] == 3, f"Expected limit 3, got {data['limit']}"
    assert isinstance(data["results"], list), "'results' should be a list."

def test_json_computed_values():
    # Recompute truth from the database to align with principles
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    # Get active modules
    cursor.execute("SELECT mod_id, mod_name FROM registry_modules WHERE current_status != 'deprecated'")
    active_modules = {row[0]: row[1] for row in cursor.fetchall()}

    # Get valid links
    cursor.execute("SELECT source_mod_id, target_mod_id FROM module_dependencies")
    links = cursor.fetchall()

    incoming = {mod_id: [] for mod_id in active_modules}
    outgoing = {mod_id: [] for mod_id in active_modules}

    for src, tgt in links:
        if src in active_modules and tgt in active_modules:
            incoming[tgt].append(active_modules[src])
            outgoing[src].append(active_modules[tgt])

    # Sort lists alphabetically
    for mod_id in active_modules:
        incoming[mod_id].sort()
        outgoing[mod_id].sort()

    # Calculate in_degree and prepare results
    results = []
    for mod_id, mod_name in active_modules.items():
        results.append({
            "module_name": mod_name,
            "in_degree": len(incoming[mod_id]),
            "incoming": incoming[mod_id],
            "outgoing": outgoing[mod_id]
        })

    # Sort results: in_degree descending, then module_name ascending
    results.sort(key=lambda x: (-x["in_degree"], x["module_name"]))

    # Paginate (limit 3)
    expected_results = results[:3]
    expected_total_active = len(active_modules)

    conn.close()

    # Validate against actual output
    with open(OUTPUT_PATH, 'r') as f:
        data = json.load(f)

    assert data["total_active_modules"] == expected_total_active, \
        f"Expected total_active_modules to be {expected_total_active}, got {data['total_active_modules']}"

    assert len(data["results"]) == 3, \
        f"Expected exactly 3 results, got {len(data['results'])}"

    for i in range(3):
        actual = data["results"][i]
        expected = expected_results[i]

        assert actual["module_name"] == expected["module_name"], \
            f"Result {i} module_name mismatch: expected {expected['module_name']}, got {actual.get('module_name')}"
        assert actual["in_degree"] == expected["in_degree"], \
            f"Result {i} in_degree mismatch: expected {expected['in_degree']}, got {actual.get('in_degree')}"
        assert actual["incoming"] == expected["incoming"], \
            f"Result {i} incoming mismatch: expected {expected['incoming']}, got {actual.get('incoming')}"
        assert actual["outgoing"] == expected["outgoing"], \
            f"Result {i} outgoing mismatch: expected {expected['outgoing']}, got {actual.get('outgoing')}"

def test_pipeline_recomputes_after_database_change():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT COALESCE(MAX(mod_id), 0) + 100 FROM registry_modules")
    dynamic_id = cursor.fetchone()[0]
    cursor.execute("SELECT mod_id FROM registry_modules WHERE current_status != 'deprecated'")
    existing_active_ids = [row[0] for row in cursor.fetchall()]

    try:
        cursor.execute(
            "INSERT INTO registry_modules (mod_id, mod_name, current_status) VALUES (?, ?, ?)",
            (dynamic_id, 'Verifier_Dynamic_Module', 'active')
        )
        cursor.executemany(
            "INSERT INTO module_dependencies (source_mod_id, target_mod_id) VALUES (?, ?)",
            [(mod_id, dynamic_id) for mod_id in existing_active_ids]
        )
        if existing_active_ids:
            cursor.execute(
                "INSERT INTO module_dependencies (source_mod_id, target_mod_id) VALUES (?, ?)",
                (dynamic_id, existing_active_ids[0])
            )
        conn.commit()

        result = subprocess.run(
            ['python3', SCRIPT_PATH],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30
        )
        assert result.returncode == 0, f"Pipeline failed on updated database: {result.stderr}"
        test_json_structure_and_metadata()
        test_json_computed_values()
    finally:
        cursor.execute(
            "DELETE FROM module_dependencies WHERE source_mod_id = ? OR target_mod_id = ?",
            (dynamic_id, dynamic_id)
        )
        cursor.execute("DELETE FROM registry_modules WHERE mod_id = ?", (dynamic_id,))
        conn.commit()
        conn.close()
        subprocess.run(['python3', SCRIPT_PATH], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
TEST_EOF

if [ -f /home/user/etl_pipeline.py ] \
   && rm -f /home/user/output/top_modules_graph.json \
   && python3 /home/user/etl_pipeline.py \
   && python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
