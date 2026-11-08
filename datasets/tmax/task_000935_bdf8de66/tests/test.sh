#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import json
import os
import pathlib
import pwd
import secrets
import stat
import subprocess
import pytest

SCRIPT_PATH = pathlib.Path('/home/user/process_logs.sh')
OUTPUT_PATH = pathlib.Path('/home/user/normalized_logs.jsonl')
USERS_PATH = pathlib.Path('/home/user/users.json')
RAW_LOGS_PATH = pathlib.Path('/home/user/raw_logs.csv')
REQUIRED_KEYS = {'log_id', 'timestamp', 'username', 'department', 'cleaned_message'}


def derive_expected():
    with USERS_PATH.open('r', encoding='utf-8') as f:
        users_list = json.load(f)
        users = {u['user_id']: u for u in users_list}

    expected_logs = {}
    with RAW_LOGS_PATH.open('r', encoding='iso-8859-1', newline='') as f:
        reader = csv.DictReader(f)
        for row in reader:
            log_id = str(row['log_id'])
            if log_id not in expected_logs:
                user = users.get(row['user_id'], {})
                expected_logs[log_id] = {
                    'log_id': log_id,
                    'timestamp': row['timestamp'],
                    'username': user.get('username', ''),
                    'department': user.get('department', ''),
                    'cleaned_message': row['message'].replace('\n', ' ')
                }
    return expected_logs


def assert_output_correct(expected_logs):
    assert OUTPUT_PATH.exists(), f"Output file not found: {OUTPUT_PATH}"
    assert OUTPUT_PATH.is_file(), f"Output path is not a regular file: {OUTPUT_PATH}"

    actual_logs = {}
    record_count = 0
    with OUTPUT_PATH.open('r', encoding='utf-8') as f:
        for line_num, line in enumerate(f, 1):
            assert line.strip(), f"Blank line found at line {line_num} in output"
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                pytest.fail(f"Invalid JSON line at line {line_num} in output: {line.rstrip()}")

            assert isinstance(obj, dict), f"Output line {line_num} is not a JSON object"
            assert set(obj.keys()) == REQUIRED_KEYS, (
                f"Output line {line_num} must contain exactly {sorted(REQUIRED_KEYS)}; "
                f"found {sorted(obj.keys())}"
            )
            assert isinstance(obj['log_id'], (str, int)) and not isinstance(obj['log_id'], bool), (
                f"log_id must be an integer or string at line {line_num}"
            )

            log_id = str(obj['log_id'])
            assert log_id not in actual_logs, f"Duplicate log_id '{log_id}' in output"
            actual_logs[log_id] = obj
            record_count += 1

    assert record_count == len(expected_logs), (
        f"Expected {len(expected_logs)} unique logs, found {record_count} output records"
    )
    assert len(actual_logs) == len(expected_logs), (
        f"Expected {len(expected_logs)} unique logs, found {len(actual_logs)}"
    )

    for log_id, expected in expected_logs.items():
        assert log_id in actual_logs, f"Missing log_id '{log_id}' in output"
        actual = actual_logs[log_id]
        assert str(actual.get('log_id')) == expected['log_id'], f"Mismatch in log_id for record {log_id}"
        assert actual.get('timestamp') == expected['timestamp'], f"Mismatch in timestamp for record {log_id}"
        assert actual.get('username') == expected['username'], f"Mismatch in username for record {log_id}"
        assert actual.get('department') == expected['department'], f"Mismatch in department for record {log_id}"
        assert actual.get('cleaned_message') == expected['cleaned_message'], (
            f"Mismatch in cleaned_message for record {log_id}. Make sure newlines are "
            "replaced by a single space and encoding is correct."
        )


def run_script_as_user():
    user = pwd.getpwnam('user')

    def demote():
        os.setgroups([])
        os.setgid(user.pw_gid)
        os.setuid(user.pw_uid)

    env = os.environ.copy()
    env['HOME'] = user.pw_dir
    result = subprocess.run(
        [str(SCRIPT_PATH)],
        cwd='/home/user',
        env=env,
        preexec_fn=demote,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"process_logs.sh exited with status {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_normalized_logs_exist_and_correct():
    assert SCRIPT_PATH.exists(), f"Script not found: {SCRIPT_PATH}"
    assert SCRIPT_PATH.is_file(), f"Script is not a regular file: {SCRIPT_PATH}"
    assert stat.S_ISREG(SCRIPT_PATH.stat().st_mode)
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script is not executable: {SCRIPT_PATH}"
    with SCRIPT_PATH.open('rb') as f:
        first_line = f.readline(256).decode('utf-8', errors='replace').lower()
    assert first_line.startswith('#!') and 'bash' in first_line, (
        "process_logs.sh must be an executable bash script with a bash shebang"
    )

    assert USERS_PATH.exists(), f"Input file missing: {USERS_PATH}"
    assert RAW_LOGS_PATH.exists(), f"Input file missing: {RAW_LOGS_PATH}"

    # Preserve and retain the original verifier's checks against the supplied fixtures.
    original_expected = derive_expected()
    assert_output_correct(original_expected)

    backups = {
        USERS_PATH: USERS_PATH.read_bytes(),
        RAW_LOGS_PATH: RAW_LOGS_PATH.read_bytes(),
        OUTPUT_PATH: OUTPUT_PATH.read_bytes() if OUTPUT_PATH.exists() else None,
    }

    try:
        token = secrets.token_hex(4)
        user_ids = [f'U{token}A', f'U{token}B', f'U{token}C']
        users = [
            {'user_id': user_ids[0], 'username': f'alice_{token}', 'department': 'engineering'},
            {'user_id': user_ids[1], 'username': f'bob_{token}', 'department': 'sales'},
            {'user_id': user_ids[2], 'username': f'charlie_{token}', 'department': 'hr'},
        ]
        USERS_PATH.write_text(json.dumps(users, ensure_ascii=False), encoding='utf-8')

        base = int(secrets.randbelow(800000) + 100000)
        rows = [
            [str(base), user_ids[0], '2026-04-01T08:00:00Z', 'Première café'],
            [str(base + 1), user_ids[1], '2026-04-01T08:01:00Z', 'Start\nmiddle\nfin naïve'],
            [str(base), user_ids[2], '2099-01-01T00:00:00Z', 'later duplicate must be discarded'],
            [str(base + 2), user_ids[2], '2026-04-01T08:02:00Z', 'comma, and "quoted" text'],
        ]
        csv_buffer = io.StringIO(newline='')
        writer = csv.writer(csv_buffer, lineterminator='\n')
        writer.writerow(['log_id', 'user_id', 'timestamp', 'message'])
        writer.writerows(rows)
        RAW_LOGS_PATH.write_bytes(csv_buffer.getvalue().encode('iso-8859-1'))

        dynamic_expected = derive_expected()
        if OUTPUT_PATH.exists():
            OUTPUT_PATH.unlink()

        run_script_as_user()
        assert_output_correct(dynamic_expected)
    finally:
        USERS_PATH.write_bytes(backups[USERS_PATH])
        RAW_LOGS_PATH.write_bytes(backups[RAW_LOGS_PATH])
        if backups[OUTPUT_PATH] is None:
            if OUTPUT_PATH.exists():
                OUTPUT_PATH.unlink()
        else:
            OUTPUT_PATH.write_bytes(backups[OUTPUT_PATH])
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
