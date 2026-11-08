#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import csv
import glob
import json
import os
import secrets
import sqlite3
import subprocess

SCRIPT_PATH = '/home/user/process_configs.py'
RAW_DIR = '/home/user/raw_configs'
DB_PATH = '/home/user/config_history.db'
CSV_PATH = '/home/user/config_summary.csv'

EXPECTED_COLUMNS = [
    'server_id',
    'timestamp',
    'hardware_ram_gb',
    'hardware_cpu_cores',
    'software_os',
    'software_is_active'
]


def normalize(config):
    active = config['software']['is_active']
    if active == 'true':
        active = 1
    elif active == 'false':
        active = 0
    return (
        config['server_id'],
        config['timestamp'],
        config['hardware']['ram_gb'],
        config['hardware']['cpu_cores'],
        config['software']['os'],
        active,
    )


def expected_csv(records):
    grouped = {}
    for server_id, timestamp, ram, cpu, software_os, active in records:
        values = grouped.setdefault(server_id, {'count': 0, 'max_ram': ram, 'active': 0})
        values['count'] += 1
        values['max_ram'] = max(values['max_ram'], ram)
        values['active'] += int(active == 1)

    rows = [['server_id', 'snapshot_count', 'max_ram_gb', 'active_snapshots']]
    for server_id in sorted(grouped):
        values = grouped[server_id]
        rows.append([
            server_id,
            str(values['count']),
            str(values['max_ram']),
            str(values['active']),
        ])
    return rows


def run_script_clean():
    for path in (DB_PATH, CSV_PATH):
        if os.path.exists(path):
            os.remove(path)
    result = subprocess.run(
        ['python3', SCRIPT_PATH],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"process_configs.py failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def check_database(expected_records, require_original_count=False):
    assert os.path.isfile(DB_PATH), f"Database file missing at {DB_PATH}"
    conn = sqlite3.connect(DB_PATH)
    try:
        cursor = conn.cursor()

        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='server_configs'")
        assert cursor.fetchone() is not None, "Table 'server_configs' does not exist in the database."

        cursor.execute("PRAGMA table_info(server_configs)")
        columns = [row[1] for row in cursor.fetchall()]
        for col in EXPECTED_COLUMNS:
            assert col in columns, f"Column '{col}' is missing from 'server_configs' table."

        cursor.execute("SELECT COUNT(*) FROM server_configs")
        count = cursor.fetchone()[0]
        if require_original_count:
            assert count == 6, f"Expected 6 rows in 'server_configs', but found {count}."
        assert count == len(expected_records), (
            f"Expected {len(expected_records)} rows derived from raw JSON files, but found {count}."
        )

        cursor.execute("SELECT software_is_active FROM server_configs WHERE software_is_active NOT IN (0, 1)")
        invalid_booleans = cursor.fetchall()
        assert len(invalid_booleans) == 0, (
            f"Found invalid values for 'software_is_active': {invalid_booleans}. Expected 0 or 1."
        )

        cursor.execute(
            "SELECT server_id, timestamp, hardware_ram_gb, hardware_cpu_cores, "
            "software_os, software_is_active FROM server_configs"
        )
        actual_records = cursor.fetchall()
        assert collections.Counter(actual_records) == collections.Counter(expected_records), (
            f"Database rows do not exactly match the normalized raw configurations.\n"
            f"Expected: {expected_records}\nActual: {actual_records}"
        )
    finally:
        conn.close()


def read_csv():
    assert os.path.isfile(CSV_PATH), f"CSV file missing at {CSV_PATH}"
    with open(CSV_PATH, 'r', newline='') as f:
        return list(csv.reader(f))


def test_complete_pipeline_and_randomized_input():
    assert os.path.isfile(SCRIPT_PATH), f"Python script missing at {SCRIPT_PATH}"

    raw_paths = sorted(glob.glob(os.path.join(RAW_DIR, '*.json')))
    baseline_files = {}
    baseline_configs = []
    for path in raw_paths:
        with open(path, 'rb') as f:
            baseline_files[path] = f.read()
        with open(path, 'r') as f:
            baseline_configs.append(json.load(f))
    baseline_records = [normalize(config) for config in baseline_configs]

    run_script_clean()
    check_database(baseline_records, require_original_count=True)

    original_expected_csv = [
        ['server_id', 'snapshot_count', 'max_ram_gb', 'active_snapshots'],
        ['srv-alpha', '3', '32', '2'],
        ['srv-beta', '2', '8', '0'],
        ['srv-gamma', '1', '64', '1']
    ]
    actual_csv = read_csv()
    assert actual_csv == original_expected_csv, (
        f"CSV content does not match expected output.\n"
        f"Expected: {original_expected_csv}\nActual: {actual_csv}"
    )
    assert actual_csv == expected_csv(baseline_records), (
        "CSV content does not match statistics derived from the raw configurations."
    )

    token = secrets.token_hex(8)
    server_id = f'zz-probe-{token}'
    ram_low = secrets.randbelow(32) + 65
    ram_high = ram_low + secrets.randbelow(32) + 1
    probe_configs = [
        {
            'server_id': server_id,
            'timestamp': 1900000000 + secrets.randbelow(100000),
            'hardware': {'ram_gb': ram_low, 'cpu_cores': 3},
            'software': {'os': f'probe-os-{token}', 'is_active': 'false'},
        },
        {
            'server_id': server_id,
            'timestamp': 1900200000 + secrets.randbelow(100000),
            'hardware': {'ram_gb': ram_high, 'cpu_cores': 7},
            'software': {'os': f'probe-os-{token}', 'is_active': 'true'},
        },
    ]
    probe_paths = [
        os.path.join(RAW_DIR, f'.verifier_probe_{token}_0.json'),
        os.path.join(RAW_DIR, f'.verifier_probe_{token}_1.json'),
    ]

    try:
        # Restore the captured inputs in case the first execution modified them.
        for path, content in baseline_files.items():
            with open(path, 'wb') as f:
                f.write(content)
        for path, config in zip(probe_paths, probe_configs):
            with open(path, 'w') as f:
                json.dump(config, f)

        probed_records = baseline_records + [normalize(config) for config in probe_configs]
        run_script_clean()
        check_database(probed_records)
        actual_probed_csv = read_csv()
        assert actual_probed_csv == expected_csv(probed_records), (
            f"CSV does not match statistics derived from all raw files.\n"
            f"Expected: {expected_csv(probed_records)}\nActual: {actual_probed_csv}"
        )
    finally:
        for path in probe_paths:
            if os.path.exists(path):
                os.remove(path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
