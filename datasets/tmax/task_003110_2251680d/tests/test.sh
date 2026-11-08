#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import csv
from collections import defaultdict

def test_script_exists_and_executable():
    script_path = "/home/user/process_graph.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

def test_json_output_correctness():
    output_path = "/home/user/same_dept_mentorships.json"
    assert os.path.isfile(output_path), f"Output JSON {output_path} does not exist."

    # Derive the expected output from the CSVs
    employees_csv = "/home/user/employees.csv"
    mentorships_csv = "/home/user/mentorships.csv"

    assert os.path.isfile(employees_csv), f"Missing {employees_csv}"
    assert os.path.isfile(mentorships_csv), f"Missing {mentorships_csv}"

    employees = {}
    with open(employees_csv, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            employees[row['emp_id']] = {
                'name': row['name'],
                'department_id': row['department_id']
            }

    expected_graph = defaultdict(list)
    with open(mentorships_csv, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            mentor_id = row['mentor_id']
            mentee_id = row['mentee_id']

            if mentor_id in employees and mentee_id in employees:
                mentor = employees[mentor_id]
                mentee = employees[mentee_id]

                if mentor['department_id'] == mentee['department_id']:
                    dept_id = mentor['department_id']
                    expected_graph[dept_id].append([mentor['name'], mentee['name']])

    # Sort the edges
    for dept_id in expected_graph:
        expected_graph[dept_id].sort(key=lambda x: (x[0], x[1]))

    # Convert defaultdict to dict
    expected_graph = dict(expected_graph)

    # Read the actual output
    with open(output_path, 'r', encoding='utf-8') as f:
        try:
            actual_graph = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {output_path} does not contain valid JSON.")

    # Sort actual edges just in case, though the prompt requires them to be sorted
    # We will assert exact match, which includes sorting order
    assert actual_graph == expected_graph, "The generated JSON does not match the expected graph structure and sorting."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
