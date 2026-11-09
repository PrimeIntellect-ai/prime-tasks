#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import shutil
import subprocess
import tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path
from uuid import uuid4

import pytest


def test_local_logs_copied():
    """Verify that all remote logs were copied without modification."""
    local_dir = Path('/home/user/local_logs')
    remote_dir = Path('/tmp/remote_logs')
    assert local_dir.is_dir(), f"Directory {local_dir} does not exist."

    assert (local_dir / 'server1.txt').is_file(), "server1.txt was not copied to local_logs."
    assert (local_dir / 'server2.txt').is_file(), "server2.txt was not copied to local_logs."

    remote_logs = sorted(remote_dir.glob('*.txt'))
    assert remote_logs, "No source log files were found."
    for remote_file in remote_logs:
        local_file = local_dir / remote_file.name
        assert local_file.is_file(), f"{remote_file.name} was not copied to local_logs."
        assert local_file.read_bytes() == remote_file.read_bytes(), \
            f"{remote_file.name} does not match the remote source file."


def test_process_logs_script_exists():
    """Verify that the Python script was created."""
    script_path = '/home/user/process_logs.py'
    assert os.path.isfile(script_path), f"Python script {script_path} does not exist."


def test_sampled_logs_json():
    """Verify the final output generated from the supplied logs is correct."""
    output_path = '/home/user/sampled_logs.json'
    assert os.path.isfile(output_path), f"Output file {output_path} does not exist."

    with open(output_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {output_path} is not valid JSON.")

    expected_data = [
        {
            "timestamp": "2024-02-14T13:00:00Z",
            "severity": "INFO",
            "message": "User logged in"
        },
        {
            "timestamp": "2024-02-14T15:00:00Z",
            "severity": "WARNING",
            "message": "Disk space low"
        },
        {
            "timestamp": "2024-02-14T15:30:00Z",
            "severity": "ERROR",
            "message": "Database connection failed"
        },
        {
            "timestamp": "2024-02-14T19:15:00Z",
            "severity": "CRITICAL",
            "message": "System crash"
        }
    ]

    assert isinstance(data, list), "The JSON output must be a list of objects."
    assert len(data) == len(expected_data), \
        f"Expected {len(expected_data)} items in the JSON array, found {len(data)}."

    for i, (actual, expected) in enumerate(zip(data, expected_data)):
        assert actual.get("timestamp") == expected["timestamp"], \
            f"Item {i}: Expected timestamp {expected['timestamp']}, got {actual.get('timestamp')}"
        assert actual.get("severity") == expected["severity"], \
            f"Item {i}: Expected severity {expected['severity']}, got {actual.get('severity')}"
        assert actual.get("message") == expected["message"], \
            f"Item {i}: Expected message '{expected['message']}', got '{actual.get('message')}'"


def test_pipeline_executes_and_handles_changed_inputs():
    """Run the submitted pipeline on fresh inputs and independently derive the result."""
    script_path = Path('/home/user/process_logs.py')
    local_dir = Path('/home/user/local_logs')
    output_path = Path('/home/user/sampled_logs.json')
    assert script_path.is_file(), f"Python script {script_path} does not exist."

    backup_root = Path(tempfile.mkdtemp(prefix='pipeline-verifier-'))
    local_backup = backup_root / 'local_logs'
    output_existed = output_path.exists()
    output_backup = output_path.read_bytes() if output_existed else None
    if local_dir.exists():
        shutil.copytree(local_dir, local_backup)

    rng = random.SystemRandom()
    base = datetime(2023, 1, 1, tzinfo=timezone.utc) + timedelta(
        days=rng.randrange(900), seconds=rng.randrange(0, 70000)
    )
    base = base.replace(microsecond=0)
    counts = {'INFO': 5, 'ERROR': 4, 'WARNING': 3, 'CRITICAL': 1}
    offsets = [-480, -300, 0, 60, 330, 570]
    records = []
    serial = 0

    for severity, count in counts.items():
        for index in range(count):
            utc_time = base + timedelta(seconds=serial * 173 + rng.randrange(1, 80))
            serial += 1
            offset_minutes = rng.choice(offsets)
            local_time = utc_time.astimezone(timezone(timedelta(minutes=offset_minutes)))
            message = f"dynamic {severity.lower()} event {index} {uuid4().hex}"
            records.append({
                'utc': utc_time,
                'severity': severity,
                'message': message,
                'line': f"{local_time.strftime('%d-%b-%Y %H:%M:%S %z')} | {severity} |   {message}   "
            })

    expected = []
    for severity in counts:
        group = sorted((r for r in records if r['severity'] == severity), key=lambda r: r['utc'])
        expected.extend(group[:math.ceil(len(group) / 4)])
    expected.sort(key=lambda r: r['utc'])
    expected_json = [
        {
            'timestamp': r['utc'].strftime('%Y-%m-%dT%H:%M:%SZ'),
            'severity': r['severity'],
            'message': r['message']
        }
        for r in expected
    ]

    try:
        if local_dir.exists():
            shutil.rmtree(local_dir)
        local_dir.mkdir(parents=True)
        rng.shuffle(records)
        buckets = [[], [], []]
        for i, record in enumerate(records):
            buckets[i % len(buckets)].append(record['line'])
        for i, lines in enumerate(buckets):
            (local_dir / f'dynamic_server_{i}.txt').write_text('\n'.join(lines) + '\n')
        (local_dir / 'ignored.dat').write_text('this non-txt file must not be processed\n')

        if output_path.exists():
            output_path.unlink()
        result = subprocess.run(
            ['/usr/bin/python3', str(script_path)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20
        )
        assert result.returncode == 0, \
            f"process_logs.py failed with exit code {result.returncode}: {result.stderr}"
        assert output_path.is_file(), "process_logs.py did not create sampled_logs.json."
        try:
            actual = json.loads(output_path.read_text())
        except json.JSONDecodeError as exc:
            pytest.fail(f"process_logs.py produced invalid JSON: {exc}")

        assert actual == expected_json, \
            f"Pipeline output for changed inputs was incorrect. Expected {expected_json}, got {actual}"
        assert all(isinstance(item, dict) and set(item) == {'timestamp', 'severity', 'message'}
                   for item in actual), \
            "Every output object must contain exactly timestamp, severity, and message."
    finally:
        if local_dir.exists():
            shutil.rmtree(local_dir)
        if local_backup.exists():
            shutil.copytree(local_backup, local_dir)
        if output_existed:
            output_path.write_bytes(output_backup)
        elif output_path.exists():
            output_path.unlink()
        shutil.rmtree(backup_root, ignore_errors=True)


def test_cron_setup():
    """Verify the cron setup file contains the exact expected string."""
    cron_path = '/home/user/cron_setup.txt'
    assert os.path.isfile(cron_path), f"Cron setup file {cron_path} does not exist."

    with open(cron_path, 'r') as f:
        content = f.read().strip()

    expected_cron = "45 * * * * /usr/bin/python3 /home/user/process_logs.py"
    assert content == expected_cron, \
        f"Cron setup file content is incorrect. Expected: '{expected_cron}', Got: '{content}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
