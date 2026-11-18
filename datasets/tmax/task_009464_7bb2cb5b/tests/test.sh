#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import stat
import subprocess
from datetime import datetime, timedelta, timezone
from pathlib import Path


def test_merged_output_exists_and_content():
    output_path = '/home/user/merged_output.jsonl'
    assert os.path.isfile(output_path), f"Output file missing: {output_path}"

    with open(output_path, 'r', encoding='utf-8') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 3, f"Expected exactly 3 lines in {output_path}, found {len(lines)}"

    expected_data = {
        101: {
            "review_timestamp_iso": "2023-01-05T14:00:00Z",
            "text_decoded": "Great app! ❤",
            "log_action": "login"
        },
        102: {
            "review_timestamp_iso": "2023-01-05T15:30:00Z",
            "text_decoded": "Broken 😭",
            "log_action": "update"
        },
        103: {
            "review_timestamp_iso": "2023-01-05T16:45:00Z",
            "text_decoded": "Me gusta la aplicación",
            "log_action": "logout"
        }
    }

    found_users = set()
    for line in lines:
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            assert False, f"Line in {output_path} is not valid JSON: {line}"

        assert "user_id" in obj, "Missing 'user_id' in output object"
        user_id = obj["user_id"]
        assert user_id in expected_data, f"Unexpected user_id {user_id} in output"
        found_users.add(user_id)

        expected = expected_data[user_id]
        assert obj.get("review_timestamp_iso") == expected["review_timestamp_iso"], f"Incorrect timestamp for user {user_id}"
        assert obj.get("text_decoded") == expected["text_decoded"], f"Incorrect decoded text for user {user_id}"
        assert obj.get("log_action") == expected["log_action"], f"Incorrect log action for user {user_id}"

        expected_keys = {"user_id", "review_timestamp_iso", "text_decoded", "log_action"}
        assert set(obj.keys()) == expected_keys, f"Object for user {user_id} has incorrect keys: {set(obj.keys())}"

    assert found_users == set(expected_data.keys()), "Missing expected users in output"


def test_run_pipeline_script():
    script_path = '/home/user/run_pipeline.sh'
    assert os.path.isfile(script_path), f"Wrapper script missing: {script_path}"
    assert os.access(script_path, os.X_OK), f"Wrapper script is not executable: {script_path}"

    with open(script_path, 'r') as f:
        content = f.read()

    assert "python" in content, "Wrapper script does not seem to invoke python"
    assert "pipeline.py" in content, "Wrapper script does not seem to invoke pipeline.py"

    pipeline_path = '/home/user/pipeline.py'
    assert os.path.isfile(pipeline_path), f"Python pipeline missing: {pipeline_path}"


def test_crontab_txt():
    crontab_path = '/home/user/crontab.txt'
    assert os.path.isfile(crontab_path), f"Crontab file missing: {crontab_path}"

    with open(crontab_path, 'r') as f:
        content = f.read().strip()

    parts = content.split()
    assert len(parts) >= 6, "Crontab entry does not have enough fields"
    assert parts[0] == "30", "Minute field in crontab should be 30"
    assert parts[1] == "2", "Hour field in crontab should be 2"
    assert parts[2] == "*", "Day of month field should be *"
    assert parts[3] == "*", "Month field should be *"
    assert parts[4] == "*", "Day of week field should be *"

    command = " ".join(parts[5:])
    assert "/home/user/run_pipeline.sh" in command, "Command in crontab does not execute the wrapper script"
    assert content == "30 2 * * * /home/user/run_pipeline.sh", "Crontab must contain the exact requested schedule and absolute command"


def test_pipeline_executes_and_handles_unseen_data():
    home = Path('/home/user')
    pipeline = home / 'pipeline.py'
    wrapper = home / 'run_pipeline.sh'
    output = home / 'merged_output.jsonl'
    reviews_path = home / 'reviews_raw.jsonl'
    logs_path = home / 'server_logs.csv'

    assert pipeline.is_file(), f"Python pipeline missing: {pipeline}"
    assert wrapper.is_file(), f"Wrapper script missing: {wrapper}"
    assert os.access(wrapper, os.X_OK), f"Wrapper script is not executable: {wrapper}"

    nonce = secrets.token_hex(6)
    first_uid = secrets.randbelow(500000) + 200000
    user_ids = [first_uid + i for i in range(5)]
    offset = secrets.randbelow(20000)
    base = datetime(2024, 2, 10, 8, 0, 0, tzinfo=timezone.utc) + timedelta(seconds=offset)
    times = [base + timedelta(days=i) for i in range(5)]

    reviews = [
        {"user_id": user_ids[0], "timestamp": times[0].strftime('%d-%b-%Y %H:%M:%S'), "text": f"{nonce} heart \\\\u2764 caf\\\\u00e9"},
        {"user_id": user_ids[1], "timestamp": times[1].strftime('%Y/%m/%d %H:%M:%S'), "text": f"{nonce} rocket \\\\uD83D\\\\uDE80"},
        {"user_id": user_ids[2], "timestamp": times[2].strftime('%d-%m-%Y %H:%M:%S'), "text": f"{nonce} espa\\\\u00f1ol"},
        {"user_id": user_ids[3], "timestamp": times[3].strftime('%d-%b-%Y %H:%M:%S'), "text": f"{nonce} outside \\\\u263A"},
        {"user_id": user_ids[4], "timestamp": times[4].strftime('%Y/%m/%d %H:%M:%S'), "text": f"{nonce} no matching user \\\\u2603"},
    ]

    def epoch(value):
        return int(value.timestamp())

    actions = {
        'early': f'early_{nonce}',
        'late': f'late_{nonce}',
        'boundary': f'boundary_{nonce}',
        'near_early': f'near_early_{nonce}',
        'near_late': f'near_late_{nonce}',
        'outside': f'outside_{nonce}',
        'wrong_user': f'wrong_{nonce}',
    }
    logs = [
        [user_ids[0], epoch(times[0] + timedelta(seconds=300)), actions['late']],
        [user_ids[0], epoch(times[0] - timedelta(seconds=300)), actions['early']],
        [user_ids[1], epoch(times[1] + timedelta(seconds=300)), actions['boundary']],
        [user_ids[2], epoch(times[2] + timedelta(seconds=1)), actions['near_late']],
        [user_ids[2], epoch(times[2] - timedelta(seconds=1)), actions['near_early']],
        [user_ids[3], epoch(times[3] + timedelta(seconds=301)), actions['outside']],
        [user_ids[4] + 10000, epoch(times[4]), actions['wrong_user']],
    ]

    with reviews_path.open('w', encoding='utf-8') as f:
        for record in reviews:
            f.write(json.dumps(record) + '\n')

    with logs_path.open('w', encoding='utf-8', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['user_id', 'log_epoch', 'action'])
        writer.writerows(logs)

    expected = {
        user_ids[0]: {
            'user_id': user_ids[0],
            'review_timestamp_iso': times[0].strftime('%Y-%m-%dT%H:%M:%SZ'),
            'text_decoded': f'{nonce} heart ❤ café',
            'log_action': actions['early'],
        },
        user_ids[1]: {
            'user_id': user_ids[1],
            'review_timestamp_iso': times[1].strftime('%Y-%m-%dT%H:%M:%SZ'),
            'text_decoded': f'{nonce} rocket 🚀',
            'log_action': actions['boundary'],
        },
        user_ids[2]: {
            'user_id': user_ids[2],
            'review_timestamp_iso': times[2].strftime('%Y-%m-%dT%H:%M:%SZ'),
            'text_decoded': f'{nonce} español',
            'log_action': actions['near_early'],
        },
    }

    if output.exists():
        output.unlink()

    saved_pipeline = home / f'.pipeline_original_{nonce}.py'
    marker = Path(f'/tmp/pipeline_executed_{nonce}')
    mode = stat.S_IMODE(pipeline.stat().st_mode)
    os.replace(pipeline, saved_pipeline)
    instrument = (
        '#!/usr/bin/env python3\n'
        'import pathlib, runpy\n'
        f'pathlib.Path({str(marker)!r}).write_text("executed", encoding="utf-8")\n'
        f'runpy.run_path({str(saved_pipeline)!r}, run_name="__main__")\n'
    )
    pipeline.write_text(instrument, encoding='utf-8')
    os.chmod(pipeline, mode)

    try:
        result = subprocess.run(
            [str(wrapper)],
            cwd='/tmp',
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
    finally:
        if pipeline.exists():
            pipeline.unlink()
        os.replace(saved_pipeline, pipeline)
        os.chmod(pipeline, mode)

    assert result.returncode == 0, f"Wrapper failed with code {result.returncode}: stdout={result.stdout!r}, stderr={result.stderr!r}"
    assert marker.is_file(), "The wrapper did not execute /home/user/pipeline.py"
    marker.unlink()
    assert output.is_file(), "Executing the wrapper did not create merged_output.jsonl"

    with output.open('r', encoding='utf-8') as f:
        raw_lines = [line.strip() for line in f if line.strip()]
    assert len(raw_lines) == len(expected), f"Expected {len(expected)} dynamically matched reviews, found {len(raw_lines)}"

    actual = {}
    required_keys = {'user_id', 'review_timestamp_iso', 'text_decoded', 'log_action'}
    for line in raw_lines:
        obj = json.loads(line)
        assert set(obj) == required_keys, f"Output object has incorrect keys: {set(obj)}"
        assert isinstance(obj['user_id'], int) and not isinstance(obj['user_id'], bool), "user_id must be an integer"
        assert obj['user_id'] not in actual, f"Duplicate output for user_id {obj['user_id']}"
        actual[obj['user_id']] = obj

    assert actual == expected, f"Pipeline output for unseen inputs was incorrect: {actual!r}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
