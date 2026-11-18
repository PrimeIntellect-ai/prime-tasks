#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import sqlite3
import math
import secrets
import shutil
import subprocess
import tempfile
from collections import defaultdict

SCRIPT_PATH = '/home/user/etl_pipeline.py'
REPORT_PATH = '/home/user/cohort_report.json'
DATA_PATH = '/home/user/data'


def get_age_group(age):
    if 18 <= age <= 25:
        return '18-25'
    elif 26 <= age <= 35:
        return '26-35'
    elif 36 <= age <= 50:
        return '36-50'
    elif age >= 51:
        return '51+'
    return 'unknown'


def compute_expected_report():
    events_dir = '/home/user/data/events'
    user_totals = defaultdict(float)

    # 1. Parse JSON session files and extract purchase events
    if os.path.exists(events_dir):
        for filename in os.listdir(events_dir):
            if filename.endswith('.json'):
                filepath = os.path.join(events_dir, filename)
                with open(filepath, 'r') as f:
                    try:
                        data = json.load(f)
                        user_id = data.get('user_id')
                        events = data.get('events', [])
                        for ev in events:
                            if ev.get('type') == 'purchase':
                                user_totals[user_id] += float(ev.get('amount', 0.0))
                    except (json.JSONDecodeError, ValueError, TypeError):
                        continue

    # 2. Query users.db
    db_path = '/home/user/data/users.db'
    if not os.path.exists(db_path):
        return []

    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    c.execute("SELECT id, country, age, status FROM users WHERE status = 'active'")
    active_users = c.fetchall()
    conn.close()

    # 3. Aggregate into cohorts
    cohort_totals = defaultdict(float)
    cohort_counts = defaultdict(int)

    for user_id, country, age, status in active_users:
        if user_id in user_totals and user_totals[user_id] > 0:
            age_group = get_age_group(age)
            cohort_key = (country, age_group)
            cohort_totals[cohort_key] += user_totals[user_id]
            cohort_counts[cohort_key] += 1

    # 4. Calculate average total spend
    cohorts = []
    for cohort_key, total_spend in cohort_totals.items():
        country, age_group = cohort_key
        count = cohort_counts[cohort_key]
        avg_spend = round(total_spend / count, 2)
        cohorts.append({
            "country": country,
            "age_group": age_group,
            "avg_spend": avg_spend
        })

    # 5. Sort cohorts
    cohorts.sort(key=lambda x: (-x["avg_spend"], x["country"]))

    # 6. Limit to top 3
    return cohorts[:3]


def test_cohort_report_exists_and_correct():
    report_path = '/home/user/cohort_report.json'
    assert os.path.exists(report_path), f"The file {report_path} was not created."

    with open(report_path, 'r') as f:
        try:
            actual_report = json.load(f)
        except json.JSONDecodeError:
            assert False, f"The file {report_path} does not contain valid JSON."

    assert isinstance(actual_report, list), f"The content of {report_path} must be a JSON array."

    expected_report = compute_expected_report()

    assert len(actual_report) == len(expected_report), f"Expected {len(expected_report)} cohorts in the report, but found {len(actual_report)}."

    for i, (actual, expected) in enumerate(zip(actual_report, expected_report)):
        assert isinstance(actual, dict), f"Item at index {i} is not a JSON object."
        assert set(actual.keys()) == {"country", "age_group", "avg_spend"}, f"Item at index {i} has incorrect keys. Expected exactly 'country', 'age_group', 'avg_spend'."
        assert actual["country"] == expected["country"], f"Cohort {i} 'country' mismatch: expected {expected['country']}, got {actual['country']}."
        assert actual["age_group"] == expected["age_group"], f"Cohort {i} 'age_group' mismatch: expected {expected['age_group']}, got {actual['age_group']}."
        assert math.isclose(actual["avg_spend"], expected["avg_spend"], rel_tol=1e-5), f"Cohort {i} 'avg_spend' mismatch: expected {expected['avg_spend']}, got {actual['avg_spend']}."


def assert_report_matches(expected_report):
    assert os.path.exists(REPORT_PATH), f"The file {REPORT_PATH} was not created by the pipeline."
    with open(REPORT_PATH, 'r') as f:
        try:
            actual_report = json.load(f)
        except json.JSONDecodeError:
            assert False, f"The file {REPORT_PATH} does not contain valid JSON."

    assert isinstance(actual_report, list), f"The content of {REPORT_PATH} must be a JSON array."
    assert len(actual_report) == len(expected_report), f"Expected {len(expected_report)} cohorts in the report, but found {len(actual_report)}."

    for i, (actual, expected) in enumerate(zip(actual_report, expected_report)):
        assert isinstance(actual, dict), f"Item at index {i} is not a JSON object."
        assert set(actual.keys()) == {"country", "age_group", "avg_spend"}, f"Item at index {i} has incorrect keys."
        assert actual["country"] == expected["country"], f"Cohort {i} country mismatch."
        assert actual["age_group"] == expected["age_group"], f"Cohort {i} age_group mismatch."
        assert isinstance(actual["avg_spend"], (int, float)) and not isinstance(actual["avg_spend"], bool), f"Cohort {i} avg_spend must be numeric."
        assert math.isclose(actual["avg_spend"], expected["avg_spend"], rel_tol=1e-5, abs_tol=1e-5), f"Cohort {i} avg_spend mismatch: expected {expected['avg_spend']}, got {actual['avg_spend']}."


def run_pipeline():
    result = subprocess.run(
        ['python3', SCRIPT_PATH],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"etl_pipeline.py failed with exit code {result.returncode}: {result.stderr}"


def test_pipeline_exists_runs_and_uses_current_inputs():
    assert os.path.isfile(SCRIPT_PATH), f"The required script {SCRIPT_PATH} does not exist or is not a regular file."
    assert not os.path.islink(SCRIPT_PATH), f"The required script {SCRIPT_PATH} must be an actual file, not a symbolic link."

    # Execute the submitted artifact against the original fixtures and verify
    # the output against values derived before execution.
    baseline_expected = compute_expected_report()
    run_pipeline()
    assert_report_matches(baseline_expected)

    backup_root = tempfile.mkdtemp(prefix='etl_verifier_')
    backup_data = os.path.join(backup_root, 'data')
    shutil.copytree(DATA_PATH, backup_data)
    report_existed = os.path.exists(REPORT_PATH)
    backup_report = os.path.join(backup_root, 'cohort_report.json')
    if report_existed:
        shutil.copy2(REPORT_PATH, backup_report)

    try:
        shutil.rmtree(DATA_PATH)
        events_dir = os.path.join(DATA_PATH, 'events')
        os.makedirs(events_dir)

        # Randomized amounts prevent a fixture-specific hard-coded report from passing.
        base = (secrets.randbelow(900000) + 100000) / 100.0
        users = [
            (101, 'A', 'Argentina', 36, 'active'),
            (102, 'B', 'Argentina', 50, 'active'),
            (103, 'C', 'Canada', 26, 'active'),
            (104, 'D', 'USA', 18, 'active'),
            (105, 'E', 'UK', 51, 'active'),
            (106, 'F', 'Japan', 35, 'inactive'),
            (107, 'G', 'France', 25, 'active'),
        ]
        conn = sqlite3.connect(os.path.join(DATA_PATH, 'users.db'))
        conn.execute('CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, country TEXT, age INTEGER, status TEXT)')
        conn.executemany('INSERT INTO users VALUES (?,?,?,?,?)', users)
        conn.commit()
        conn.close()

        sessions = [
            {'session_id': 'r1', 'user_id': 101, 'events': [{'type': 'pageview'}, {'type': 'purchase', 'amount': base + 300.0}, {'type': 'purchase', 'amount': 100.0}]},
            {'session_id': 'r2', 'user_id': 102, 'events': [{'type': 'purchase', 'amount': base + 600.0}]},
            {'session_id': 'r3', 'user_id': 103, 'events': [{'type': 'purchase', 'amount': base + 500.0}]},
            {'session_id': 'r4', 'user_id': 104, 'events': [{'type': 'purchase', 'amount': base + 100.0}]},
            {'session_id': 'r5', 'user_id': 104, 'events': [{'type': 'purchase', 'amount': 100.0}]},
            {'session_id': 'r6', 'user_id': 105, 'events': [{'type': 'purchase', 'amount': base + 50.0}]},
            {'session_id': 'r7', 'user_id': 106, 'events': [{'type': 'purchase', 'amount': base + 10000.0}]},
            {'session_id': 'r8', 'user_id': 107, 'events': [{'type': 'pageview'}]},
        ]
        for i, session in enumerate(sessions):
            with open(os.path.join(events_dir, f'random_session_{i}.json'), 'w') as f:
                json.dump(session, f)

        mutated_expected = compute_expected_report()
        if os.path.exists(REPORT_PATH):
            os.remove(REPORT_PATH)
        run_pipeline()
        assert_report_matches(mutated_expected)
    finally:
        if os.path.exists(DATA_PATH):
            shutil.rmtree(DATA_PATH)
        shutil.copytree(backup_data, DATA_PATH)
        if os.path.exists(REPORT_PATH):
            os.remove(REPORT_PATH)
        if report_existed:
            shutil.copy2(backup_report, REPORT_PATH)
        shutil.rmtree(backup_root)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
