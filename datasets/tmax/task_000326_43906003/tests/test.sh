#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import hashlib
import json
import os
import pwd
import re
import secrets
import shutil
import subprocess
from collections import Counter
from datetime import datetime

import pytest


def test_run_pipeline_sh_executable():
    script_path = '/home/user/run_pipeline.sh'
    assert os.path.isfile(script_path), f"The script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"The script {script_path} is not executable."


def test_cron_job_installed():
    try:
        result = subprocess.run(
            ['crontab', '-l', '-u', 'user'],
            capture_output=True,
            text=True,
            check=True,
        )
        crontab_output = result.stdout
    except subprocess.CalledProcessError:
        cron_file = '/var/spool/cron/crontabs/user'
        if os.path.isfile(cron_file):
            with open(cron_file, 'r') as f:
                crontab_output = f.read()
        else:
            pytest.fail("Failed to retrieve crontab for 'user' and cron file does not exist.")

    pattern = r"30\s+2\s+\*\s+\*\s+\*\s+/home/user/run_pipeline\.sh"
    assert re.search(pattern, crontab_output), "The required cron job is not installed or incorrectly formatted."


def test_clean_merged_csv_content():
    output_file = '/home/user/output/clean_merged.csv'
    assert os.path.isfile(output_file), f"The output file {output_file} does not exist."

    expected_data = [
        ['id', 'name', 'email', 'join_date', 'activity_count'],
        ['1', 'Alice Smith', 'alice@example.com', '2023-01-15', '2'],
        ['2', 'Bob Jones', 'bob@example.com', '2022-12-31', '1'],
        ['3', 'Carol White', 'carol@example.org', '2023-02-01', '0'],
        ['5', 'Dave Brown', 'dave.brown@example.com', '2021-10-10', '1'],
        ['6', 'Eve Black', 'eve@example.com', '2023-03-05', '3'],
    ]

    with open(output_file, 'r', newline='') as f:
        actual_data = list(csv.reader(f))

    assert actual_data == expected_data, "The contents of clean_merged.csv do not match the expected normalized, deduplicated, and merged data."


def test_pipeline_log_format():
    log_file = '/home/user/pipeline.log'
    assert os.path.isfile(log_file), f"The log file {log_file} does not exist."

    with open(log_file, 'r') as f:
        lines = f.readlines()

    assert len(lines) > 0, f"The log file {log_file} is empty."
    pattern = re.compile(r"^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] SUCCESS: Processed 5 unique users\.$")
    assert any(pattern.match(line.strip()) for line in lines), "The expected success log line was not found in pipeline.log or did not match the required format."


def test_pipeline_executes_on_fresh_inputs():
    token = secrets.token_hex(6)
    base_id = 1000 + secrets.randbelow(8000)
    users = [
        [str(base_id), 'mARY aNN', f'Alpha.{token}@Example.NET', '04/09/2024'],
        [str(base_id + 1), 'SECOND user', f'beta.{token}@example.net', '2022-11-30'],
        [str(base_id + 2), 'duplicate person', f'ALPHA.{token}@EXAMPLE.NET', '01/01/2020'],
        [str(base_id + 3), 'tHIRD pERSON', f'gamma.{token}@example.org', '7/05/2021'],
        [str(base_id + 4), 'FOURTH PERSON', f'delta.{token}@example.com', '2020-02-29'],
    ]
    activities = [
        {'user_email': f'ALPHA.{token}@EXAMPLE.NET', 'action': 'login'},
        {'user_email': f'alpha.{token}@example.net', 'action': 'logout'},
        {'user_email': f'BETA.{token}@EXAMPLE.NET', 'action': 'click'},
        {'user_email': f'gamma.{token}@example.org', 'action': 'view'},
        {'user_email': f'GAMMA.{token}@EXAMPLE.ORG', 'action': 'login'},
        {'user_email': f'gamma.{token}@example.org', 'action': 'logout'},
        {'user_email': f'unknown.{token}@example.com', 'action': 'bounce'},
    ]

    user_info = pwd.getpwnam('user')
    users_path = '/home/user/data/users.csv'
    activity_path = '/home/user/data/activity.jsonl'
    output_path = '/home/user/output/clean_merged.csv'
    log_path = '/home/user/pipeline.log'

    with open(users_path, 'w', newline='') as f:
        writer = csv.writer(f, lineterminator='\n')
        writer.writerow(['id', 'name', 'email', 'join_date'])
        writer.writerows(users)
    with open(activity_path, 'w') as f:
        for item in activities:
            f.write(json.dumps(item) + '\n')

    sentinel = f'preexisting-log-{token}\n'
    with open(log_path, 'w') as f:
        f.write(sentinel)

    for path in (users_path, activity_path, log_path):
        os.chown(path, user_info.pw_uid, user_info.pw_gid)
        os.chmod(path, 0o666)
    os.chown('/home/user/output', user_info.pw_uid, user_info.pw_gid)
    os.chmod('/home/user/output', 0o777)

    if os.path.lexists(output_path):
        if os.path.isdir(output_path) and not os.path.islink(output_path):
            shutil.rmtree(output_path)
        else:
            os.unlink(output_path)

    activity_counts = Counter(item['user_email'].lower() for item in activities)
    expected = [['id', 'name', 'email', 'join_date', 'activity_count']]
    seen_hashes = set()
    for row_id, name, email, join_date in users:
        normalized_email = email.lower()
        digest = hashlib.md5(normalized_email.encode('utf-8')).hexdigest()
        if digest in seen_hashes:
            continue
        seen_hashes.add(digest)
        if '/' in join_date:
            normalized_date = datetime.strptime(join_date, '%m/%d/%Y').strftime('%Y-%m-%d')
        else:
            normalized_date = datetime.strptime(join_date, '%Y-%m-%d').strftime('%Y-%m-%d')
        expected.append([
            row_id,
            name.title(),
            normalized_email,
            normalized_date,
            str(activity_counts[normalized_email]),
        ])

    runuser = shutil.which('runuser')
    assert runuser, 'runuser is unavailable'
    result = subprocess.run(
        [runuser, '-u', 'user', '--', '/home/user/run_pipeline.sh'],
        cwd='/home/user',
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"Pipeline execution failed. stdout={result.stdout!r} stderr={result.stderr!r}"
    assert os.path.isfile(output_path), 'Pipeline did not create clean_merged.csv for the fresh inputs.'

    with open(output_path, 'r', newline='') as f:
        actual = list(csv.reader(f))
    assert actual == expected, 'Pipeline output for fresh randomized inputs is incorrect.'

    with open(log_path, 'r') as f:
        log_lines = f.read().splitlines()
    assert log_lines and log_lines[0] == sentinel.strip(), 'Pipeline did not append to the existing log.'
    success_pattern = re.compile(
        rf"^\[\d{{4}}-\d{{2}}-\d{{2}} \d{{2}}:\d{{2}}:\d{{2}}\] SUCCESS: Processed {len(expected) - 1} unique users\.$"
    )
    assert any(success_pattern.fullmatch(line) for line in log_lines[1:]), 'The executed pipeline did not append the required success line.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
