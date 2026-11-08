#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import pytest

def test_enriched_projects_exists():
    output_file = "/home/user/output/enriched_projects.jsonl"
    assert os.path.isfile(output_file), f"Output file {output_file} does not exist. The ETL pipeline did not complete successfully or saved to the wrong location."

def test_enriched_projects_content():
    emp_file = "/home/user/data/employees.jsonl"
    proj_file = "/home/user/data/projects.jsonl"
    output_file = "/home/user/output/enriched_projects.jsonl"

    assert os.path.isfile(emp_file), "Input employees file is missing."
    assert os.path.isfile(proj_file), "Input projects file is missing."
    assert os.path.isfile(output_file), "Output file is missing."

    # Load input data
    employees = {}
    with open(emp_file, 'r') as f:
        for line in f:
            if line.strip():
                emp = json.loads(line)
                employees[emp["emp_id"]] = emp

    projects = []
    with open(proj_file, 'r') as f:
        for line in f:
            if line.strip():
                projects.append(json.loads(line))

    # Compute expected output
    expected_output = []
    for proj in projects:
        team_skills = set()
        manager_skills = set()

        for member_id in proj.get("members", []):
            member = employees.get(member_id)
            if not member:
                continue

            # Add member skills
            team_skills.update(member.get("skills", []))

            # Add manager skills
            manager_id = member.get("manager_id")
            if manager_id:
                manager = employees.get(manager_id)
                if manager:
                    manager_skills.update(manager.get("skills", []))

        # Exclude team skills from manager oversight skills
        manager_oversight_skills = manager_skills - team_skills

        expected_record = {
            "proj_id": proj["proj_id"],
            "proj_name": proj["name"],
            "team_skills": sorted(list(team_skills)),
            "manager_oversight_skills": sorted(list(manager_oversight_skills))
        }
        expected_output.append(expected_record)

    # Sort expected output by proj_id as required
    expected_output.sort(key=lambda x: x["proj_id"])

    # Load actual output
    actual_output = []
    with open(output_file, 'r') as f:
        for line in f:
            if line.strip():
                try:
                    actual_output.append(json.loads(line))
                except json.JSONDecodeError:
                    pytest.fail("Output file contains invalid JSON lines.")

    # Validate output structure and content
    assert len(actual_output) == len(expected_output), f"Expected {len(expected_output)} records in output, but found {len(actual_output)}."

    for i, (actual, expected) in enumerate(zip(actual_output, expected_output)):
        assert actual.get("proj_id") == expected["proj_id"], f"Record {i} proj_id mismatch. Expected {expected['proj_id']}, got {actual.get('proj_id')}. Ensure output is sorted by proj_id."
        assert actual.get("proj_name") == expected["proj_name"], f"Record {i} proj_name mismatch for project {expected['proj_id']}."

        actual_team_skills = actual.get("team_skills", [])
        expected_team_skills = expected["team_skills"]
        assert actual_team_skills == expected_team_skills, f"team_skills mismatch for project {expected['proj_id']}. Expected {expected_team_skills}, got {actual_team_skills}."

        actual_manager_skills = actual.get("manager_oversight_skills", [])
        expected_manager_skills = expected["manager_oversight_skills"]
        assert actual_manager_skills == expected_manager_skills, f"manager_oversight_skills mismatch for project {expected['proj_id']}. Expected {expected_manager_skills}, got {actual_manager_skills}."

        # Verify strict schema compliance (no extra fields)
        expected_keys = {"proj_id", "proj_name", "team_skills", "manager_oversight_skills"}
        actual_keys = set(actual.keys())
        extra_keys = actual_keys - expected_keys
        missing_keys = expected_keys - actual_keys
        assert not extra_keys, f"Project {expected['proj_id']} contains unexpected extra properties: {extra_keys}"
        assert not missing_keys, f"Project {expected['proj_id']} is missing required properties: {missing_keys}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
