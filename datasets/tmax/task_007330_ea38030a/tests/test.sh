#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import sqlite3

ORIGINAL_EXPECTED_DATA = [
    {
        "trial_id": 1001,
        "date": "2023-10-01",
        "outcome": "Success",
        "score": 85.5,
        "subject": {
            "subject_id": 101,
            "age": 45,
            "cohort_group": "Control",
            "site": {
                "site_id": 1,
                "name": "Alpha Lab",
                "location": "New York"
            }
        }
    },
    {
        "trial_id": 1002,
        "date": "2023-10-15",
        "outcome": "Failure",
        "score": 42.0,
        "subject": {
            "subject_id": 101,
            "age": 45,
            "cohort_group": "Control",
            "site": {
                "site_id": 1,
                "name": "Alpha Lab",
                "location": "New York"
            }
        }
    },
    {
        "trial_id": 1003,
        "date": "2023-11-02",
        "outcome": "Success",
        "score": 91.2,
        "subject": {
            "subject_id": 102,
            "age": 38,
            "cohort_group": "Treatment A",
            "site": {
                "site_id": 1,
                "name": "Alpha Lab",
                "location": "New York"
            }
        }
    },
    {
        "trial_id": 1004,
        "date": "2023-11-10",
        "outcome": "Partial",
        "score": 68.9,
        "subject": {
            "subject_id": 103,
            "age": 50,
            "cohort_group": "Treatment B",
            "site": {
                "site_id": 2,
                "name": "Beta Clinic",
                "location": "London"
            }
        }
    }
]

def test_denormalized_trials_json_exists():
    output_path = "/home/user/denormalized_trials.json"
    assert os.path.exists(output_path), f"Output file {output_path} does not exist."
    assert os.path.isfile(output_path), f"{output_path} is not a file."

def test_denormalized_trials_json_content():
    output_path = "/home/user/denormalized_trials.json"
    db_path = "/home/user/research_data.db"

    assert os.path.exists(db_path), f"Database file {db_path} is missing."

    try:
        with open(output_path, "r") as f:
            student_data = json.load(f)
    except json.JSONDecodeError:
        assert False, f"{output_path} is not a valid JSON file."

    assert isinstance(student_data, list), "Output JSON must be an array of objects."

    try:
        conn = sqlite3.connect(db_path)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        query = """
        SELECT
            t.id as trial_id, t.date, t.outcome, t.score,
            sub.id as subject_id, sub.age, sub.group_name as cohort_group,
            s.id as site_id, s.name as site_name, s.location as site_location
        FROM trials t
        JOIN subjects sub ON t.subject_id = sub.id
        JOIN sites s ON sub.site_id = s.id
        """
        cursor.execute(query)
        rows = cursor.fetchall()
        conn.close()
    except sqlite3.Error as e:
        assert False, f"Failed to query database to generate truth data: {e}"

    expected_data = []
    for row in rows:
        expected_data.append({
            "trial_id": row["trial_id"],
            "date": row["date"],
            "outcome": row["outcome"],
            "score": row["score"],
            "subject": {
                "subject_id": row["subject_id"],
                "age": row["age"],
                "cohort_group": row["cohort_group"],
                "site": {
                    "site_id": row["site_id"],
                    "name": row["site_name"],
                    "location": row["site_location"]
                }
            }
        })

    expected_data_sorted = sorted(expected_data, key=lambda x: x["trial_id"])
    original_data_sorted = sorted(ORIGINAL_EXPECTED_DATA, key=lambda x: x["trial_id"])
    assert expected_data_sorted == original_data_sorted, "The source database contents were modified from the original dataset."

    student_data_sorted = sorted(student_data, key=lambda x: x.get("trial_id", -1))

    assert len(student_data_sorted) == len(expected_data_sorted), f"Expected {len(expected_data_sorted)} trials, found {len(student_data_sorted)}."

    for student_item, expected_item in zip(student_data_sorted, expected_data_sorted):
        assert student_item == expected_item, f"Mismatch at trial_id {expected_item['trial_id']}. Expected: {expected_item}, Got: {student_item}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
