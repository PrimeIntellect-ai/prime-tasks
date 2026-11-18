#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import hashlib
import subprocess
import csv
from datetime import datetime, timezone

def parse_timestamp(t):
    if isinstance(t, int):
        return t
    if 'T' in t:
        dt = datetime.strptime(t, "%Y-%m-%dT%H:%M:%SZ")
        return int(dt.replace(tzinfo=timezone.utc).timestamp())
    else:
        dt = datetime.strptime(t, "%Y-%m-%d %H:%M:%S")
        return int(dt.replace(tzinfo=timezone.utc).timestamp())

def compute_expected_changelog(input_path):
    records = []
    with open(input_path, 'r') as f:
        for line in f:
            if not line.strip():
                continue
            data = json.loads(line)
            server_id = data['server_id']
            ts = parse_timestamp(data['reported_at'])

            cfg = data.get('config_data', {})
            app_version = cfg.get('app_version', '')
            max_conns = cfg.get('max_conns', 0)
            tls_bool = cfg.get('features', {}).get('tls', False)
            tls_str = 'true' if tls_bool else 'false'

            canon_str = f"{app_version}|{max_conns}|{tls_str}"
            cfg_hash = hashlib.sha256(canon_str.encode('utf-8')).hexdigest()

            records.append({
                'server_id': server_id,
                'timestamp': ts,
                'config_hash': cfg_hash,
                'app_version': app_version,
                'max_conns': max_conns,
                'tls': tls_str
            })

    # Sort by server_id alphabetically, then timestamp ascending
    records.sort(key=lambda x: (x['server_id'], x['timestamp']))

    # Deduplicate
    deduped = []
    last_hash_per_server = {}

    for r in records:
        sid = r['server_id']
        if sid not in last_hash_per_server or last_hash_per_server[sid] != r['config_hash']:
            deduped.append(r)
            last_hash_per_server[sid] = r['config_hash']

    return deduped

def test_go_module_and_binary():
    """Test that the Go module is initialized and binary is built."""
    app_dir = "/home/user/app"
    assert os.path.isfile(os.path.join(app_dir, "go.mod")), "Go module not initialized (go.mod missing)."

    binary_path = os.path.join(app_dir, "tracker")
    assert os.path.isfile(binary_path), "Go binary 'tracker' not found in /home/user/app/."
    assert os.access(binary_path, os.X_OK), "The 'tracker' file is not executable."

def test_systemd_service_configuration():
    """Test that the systemd service file is created correctly."""
    service_path = "/etc/systemd/system/config-tracker.service"
    assert os.path.isfile(service_path), f"Systemd service file missing at {service_path}."

    with open(service_path, 'r') as f:
        content = f.read()

    assert "ExecStart=/home/user/app/tracker" in content, "Service does not execute /home/user/app/tracker."
    assert "WorkingDirectory=/home/user/app" in content, "Service does not set WorkingDirectory=/home/user/app."
    assert "User=user" in content, "Service does not run as User=user."

def test_systemd_service_enabled():
    """Test that the systemd service is enabled."""
    result = subprocess.run(['systemctl', 'is-enabled', 'config-tracker.service'], capture_output=True, text=True)
    assert result.returncode == 0 and 'enabled' in result.stdout.strip(), "config-tracker.service is not enabled."

def test_output_csv_correctness():
    """Test that the output CSV matches the expected deduplicated timeline."""
    input_file = "/home/user/input/configs.jsonl"
    output_file = "/home/user/output/changelog.csv"

    assert os.path.isfile(output_file), f"Output file {output_file} is missing. Did the service run?"

    expected_records = compute_expected_changelog(input_file)

    with open(output_file, 'r') as f:
        reader = csv.DictReader(f)
        actual_records = list(reader)

    expected_header = ["server_id", "timestamp", "config_hash", "app_version", "max_conns", "tls"]
    assert reader.fieldnames == expected_header, f"CSV header incorrect. Expected {expected_header}, got {reader.fieldnames}"

    assert len(actual_records) == len(expected_records), f"Expected {len(expected_records)} records, but got {len(actual_records)}."

    for i, (actual, expected) in enumerate(zip(actual_records, expected_records)):
        assert actual['server_id'] == expected['server_id'], f"Row {i+1}: expected server_id {expected['server_id']}, got {actual['server_id']}"
        assert str(actual['timestamp']) == str(expected['timestamp']), f"Row {i+1}: expected timestamp {expected['timestamp']}, got {actual['timestamp']}"
        assert actual['config_hash'] == expected['config_hash'], f"Row {i+1}: expected config_hash {expected['config_hash']}, got {actual['config_hash']}"
        assert actual['app_version'] == expected['app_version'], f"Row {i+1}: expected app_version {expected['app_version']}, got {actual['app_version']}"
        assert str(actual['max_conns']) == str(expected['max_conns']), f"Row {i+1}: expected max_conns {expected['max_conns']}, got {actual['max_conns']}"
        assert actual['tls'] == expected['tls'], f"Row {i+1}: expected tls {expected['tls']}, got {actual['tls']}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
