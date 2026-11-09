#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import csv
import sqlite3
import pytest

DB_PATH = '/home/user/research_data.db'
EXPORT_DIR = '/home/user/export'
JSON_PATH = os.path.join(EXPORT_DIR, 'subjects.json')
NODES_PATH = os.path.join(EXPORT_DIR, 'nodes.csv')
EDGES_PATH = os.path.join(EXPORT_DIR, 'edges.csv')

@pytest.fixture(scope="module")
def db_data():
    if not os.path.exists(DB_PATH):
        pytest.fail(f"Database {DB_PATH} does not exist.")

    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    cursor.execute("SELECT * FROM subjects")
    subjects = [dict(row) for row in cursor.fetchall()]

    cursor.execute("SELECT * FROM trial_runs")
    trials = [dict(row) for row in cursor.fetchall()]

    cursor.execute("SELECT * FROM sensor_data")
    measurements = [dict(row) for row in cursor.fetchall()]

    conn.close()

    return {
        'subjects': subjects,
        'trials': trials,
        'measurements': measurements
    }

def test_json_export(db_data):
    assert os.path.exists(JSON_PATH), f"JSON file {JSON_PATH} is missing."

    with open(JSON_PATH, 'r', encoding='utf-8') as f:
        try:
            actual_json = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{JSON_PATH} is not a valid JSON file.")

    # Build expected JSON from db_data
    expected_json = []
    for sub in db_data['subjects']:
        sub_dict = dict(sub)
        sub_dict['trials'] = []
        for trial in db_data['trials']:
            if trial['subject_id'] == sub['sub_id']:
                trial_dict = dict(trial)
                trial_dict['measurements'] = []
                for meas in db_data['measurements']:
                    if meas['t_id'] == trial['trial_id']:
                        trial_dict['measurements'].append(dict(meas))

                # Sort measurements by meas_id to ensure order-independent comparison
                trial_dict['measurements'] = sorted(trial_dict['measurements'], key=lambda x: x['meas_id'])
                sub_dict['trials'].append(trial_dict)

        # Sort trials by trial_id
        sub_dict['trials'] = sorted(sub_dict['trials'], key=lambda x: x['trial_id'])
        expected_json.append(sub_dict)

    expected_json = sorted(expected_json, key=lambda x: x['sub_id'])

    # Process actual JSON similarly for comparison
    if not isinstance(actual_json, list):
        pytest.fail("JSON root must be an array.")

    for sub in actual_json:
        if 'trials' in sub:
            for trial in sub['trials']:
                if 'measurements' in trial:
                    trial['measurements'] = sorted(trial['measurements'], key=lambda x: x.get('meas_id', 0))
            sub['trials'] = sorted(sub['trials'], key=lambda x: x.get('trial_id', 0))
    actual_json = sorted(actual_json, key=lambda x: x.get('sub_id', 0))

    assert actual_json == expected_json, "JSON export does not match the database contents."

def test_nodes_csv_export(db_data):
    assert os.path.exists(NODES_PATH), f"Nodes CSV {NODES_PATH} is missing."

    with open(NODES_PATH, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        actual_nodes = list(reader)

    assert reader.fieldnames == ['node_id', 'node_type', 'label'], f"Nodes CSV headers are incorrect: {reader.fieldnames}"

    expected_nodes = []
    for sub in db_data['subjects']:
        expected_nodes.append({'node_id': f"sub_{sub['sub_id']}", 'node_type': 'Subject', 'label': str(sub['name'])})
    for trial in db_data['trials']:
        expected_nodes.append({'node_id': f"trial_{trial['trial_id']}", 'node_type': 'Trial', 'label': str(trial['condition'])})
    for meas in db_data['measurements']:
        expected_nodes.append({'node_id': f"meas_{meas['meas_id']}", 'node_type': 'Measurement', 'label': str(meas['sensor'])})

    def sort_key(d):
        return (d.get('node_id', ''), d.get('node_type', ''), d.get('label', ''))

    actual_nodes_sorted = sorted(actual_nodes, key=sort_key)
    expected_nodes_sorted = sorted(expected_nodes, key=sort_key)

    assert actual_nodes_sorted == expected_nodes_sorted, "Nodes CSV export does not match expected data."

def test_edges_csv_export(db_data):
    assert os.path.exists(EDGES_PATH), f"Edges CSV {EDGES_PATH} is missing."

    with open(EDGES_PATH, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        actual_edges = list(reader)

    assert reader.fieldnames == ['source', 'target', 'relation'], f"Edges CSV headers are incorrect: {reader.fieldnames}"

    expected_edges = []
    for trial in db_data['trials']:
        expected_edges.append({
            'source': f"sub_{trial['subject_id']}",
            'target': f"trial_{trial['trial_id']}",
            'relation': 'HAS_TRIAL'
        })
    for meas in db_data['measurements']:
        expected_edges.append({
            'source': f"trial_{meas['t_id']}",
            'target': f"meas_{meas['meas_id']}",
            'relation': 'HAS_MEASUREMENT'
        })

    def sort_key(d):
        return (d.get('source', ''), d.get('target', ''), d.get('relation', ''))

    actual_edges_sorted = sorted(actual_edges, key=sort_key)
    expected_edges_sorted = sorted(expected_edges, key=sort_key)

    assert actual_edges_sorted == expected_edges_sorted, "Edges CSV export does not match expected data."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
