#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import math
import os
import secrets
import shutil
import signal
import subprocess
import tempfile
import threading
from collections import Counter, defaultdict
from pathlib import Path

import pytest

OUTPUT_FILE = "/home/user/output_data/processed_combined.csv"
EXPECTED_HEADERS = ['site_id', 'timestamp', 'sensor_name', 'reading', 'rolling_avg', 'notes']
SENSORS = ['sensor_alpha', 'sensor_beta', 'sensor_gamma']

ORIGINAL_SOURCES = {
    'site_1': [
        ('2023-01-01T10:00:00Z', '10.0', '20.0', '30.0', 'Start of year\nsystem check'),
        ('2023-01-01T10:05:00Z', '12.0', '', '32.0', 'Normal'),
        ('2023-01-01T10:10:00Z', '14.0', '22.0', '34.0', 'Normal\nwith extra newline'),
        ('2023-01-01T10:15:00Z', '16.0', '24.0', '36.0', 'End of run'),
    ],
    'site_2': [
        ('2023-01-01T10:00:00Z', '100.0', '200.0', '300.0', 'All good'),
        ('2023-01-01T10:05:00Z', '110.0', '210.0', '', 'Missing gamma\nneeds fixing'),
        ('2023-01-01T10:10:00Z', '120.0', '220.0', '320.0', 'Restored'),
    ],
    'site_3': [
        ('2023-01-01T10:00:00Z', '1.0', '2.0', '3.0', 'Site 3 active'),
    ],
    'site_4': [],
}


def expected_rows(sources):
    groups = defaultdict(list)
    for site, records in sources.items():
        for timestamp, alpha, beta, gamma, notes in records:
            values = dict(zip(SENSORS, (alpha, beta, gamma)))
            for sensor, raw in values.items():
                if raw == '' or raw.lower() == 'nan':
                    continue
                groups[(site, sensor)].append((timestamp, float(raw), notes))

    result = []
    for (site, sensor), records in groups.items():
        records.sort(key=lambda item: item[0])
        prior = []
        for timestamp, reading, notes in records:
            prior.append(reading)
            rolling = round(sum(prior[-3:]) / len(prior[-3:]), 2)
            result.append((site, timestamp, sensor, reading, rolling, notes))
    return result


def load_output(path=OUTPUT_FILE):
    with open(path, 'r', newline='', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == EXPECTED_HEADERS
        rows = list(reader)
    for row in rows:
        assert None not in row, f"Malformed or extra CSV fields in row: {row}"
        assert set(row) == set(EXPECTED_HEADERS)
    return rows


def assert_complete_output(path, sources):
    rows = load_output(path)
    expected = expected_rows(sources)
    assert len(rows) == len(expected), f"Expected {len(expected)} rows, got {len(rows)}"

    actual_by_key = {}
    actual_order = defaultdict(list)
    for row in rows:
        key = (row['site_id'], row['timestamp'], row['sensor_name'])
        assert key not in actual_by_key, f"Duplicate output record: {key}"
        assert row['site_id'] in sources, f"Unexpected site: {row['site_id']}"
        assert row['sensor_name'] in SENSORS, f"Unexpected sensor: {row['sensor_name']}"
        assert row['reading'] != '', f"Empty reading in {key}"
        reading = float(row['reading'])
        rolling = float(row['rolling_avg'])
        assert math.isfinite(reading), f"Non-finite reading in {key}"
        assert math.isfinite(rolling), f"Non-finite rolling average in {key}"
        actual_by_key[key] = (reading, rolling, row['notes'])
        actual_order[(row['site_id'], row['sensor_name'])].append(row['timestamp'])

    expected_keys = {(site, timestamp, sensor) for site, timestamp, sensor, _, _, _ in expected}
    assert set(actual_by_key) == expected_keys, "Output has missing or unexpected unpivoted records"

    for site, timestamp, sensor, reading, rolling, notes in expected:
        actual_reading, actual_rolling, actual_notes = actual_by_key[(site, timestamp, sensor)]
        assert actual_reading == pytest.approx(reading)
        assert actual_rolling == pytest.approx(rolling)
        assert actual_notes == notes

    for group, timestamps in actual_order.items():
        assert timestamps == sorted(timestamps), f"Records are not chronological for {group}"


def test_output_file_exists():
    assert os.path.isfile(OUTPUT_FILE), f"Output file {OUTPUT_FILE} is missing."


def test_output_headers():
    with open(OUTPUT_FILE, 'r', newline='', encoding='utf-8') as f:
        reader = csv.reader(f)
        headers = next(reader, None)
    assert headers == EXPECTED_HEADERS, f"Headers are incorrect. Expected {EXPECTED_HEADERS}, got {headers}."


def test_rolling_averages_and_data():
    rows = load_output()
    assert len(rows) > 0, "The output CSV is empty."

    alpha_row = next((r for r in rows if r['site_id'] == 'site_1' and r['sensor_name'] == 'sensor_alpha' and r['timestamp'] == '2023-01-01T10:15:00Z'), None)
    assert alpha_row is not None, "Missing record for site_1, sensor_alpha at 2023-01-01T10:15:00Z"
    assert float(alpha_row['reading']) == 16.0, f"Expected reading 16.0, got {alpha_row['reading']}"
    assert float(alpha_row['rolling_avg']) == 14.0, f"Expected rolling_avg 14.0, got {alpha_row['rolling_avg']}"

    beta_row = next((r for r in rows if r['site_id'] == 'site_1' and r['sensor_name'] == 'sensor_beta' and r['timestamp'] == '2023-01-01T10:10:00Z'), None)
    assert beta_row is not None, "Missing record for site_1, sensor_beta at 2023-01-01T10:10:00Z"
    assert float(beta_row['reading']) == 22.0, f"Expected reading 22.0, got {beta_row['reading']}"
    assert float(beta_row['rolling_avg']) == 21.0, f"Expected rolling_avg 21.0, got {beta_row['rolling_avg']}"


def test_multiline_notes_preserved():
    rows = load_output()
    multiline_row = next((r for r in rows if r['site_id'] == 'site_1' and r['timestamp'] == '2023-01-01T10:00:00Z'), None)
    assert multiline_row is not None, "Missing record for site_1 at 2023-01-01T10:00:00Z"
    assert "\n" in multiline_row['notes'], "Multiline note did not preserve embedded newlines."


def test_all_original_records_order_values_notes_and_rolling_averages():
    assert_complete_output(OUTPUT_FILE, ORIGINAL_SOURCES)


def find_processing_script():
    candidates = []
    excluded = {Path('/home/user/input_data'), Path('/home/user/output_data')}
    for path in Path('/home/user').rglob('*'):
        if not path.is_file() or any(parent in excluded for parent in path.parents):
            continue
        if path.stat().st_size > 2_000_000:
            continue
        if path.suffix.lower() not in {'.py', '.sh', '.r', '.pl', '.rb', '.js'} and not os.access(path, os.X_OK):
            continue
        try:
            text = path.read_text(encoding='utf-8', errors='ignore')
        except OSError:
            continue
        score = 0
        score += 4 if 'processed_combined.csv' in text else 0
        score += 3 if 'input_data' in text else 0
        score += 2 if 'sensor_alpha' in text or 'sensor_name' in text else 0
        score += 1 if 'rolling' in text or 'moving' in text else 0
        if score >= 7:
            candidates.append((score, path))
    assert candidates, "No self-contained processing script was found under /home/user"
    candidates.sort(key=lambda item: (item[0], item[1].stat().st_mtime), reverse=True)
    return candidates[0][1]


def command_for(path):
    suffix = path.suffix.lower()
    if suffix == '.py':
        return ['python3', str(path)]
    if suffix == '.sh':
        return ['bash', str(path)]
    if suffix == '.r':
        return ['Rscript', str(path)]
    if suffix == '.pl':
        return ['perl', str(path)]
    if suffix == '.rb':
        return ['ruby', str(path)]
    if suffix == '.js':
        return ['node', str(path)]
    return [str(path)]


def csv_text(records):
    stream = io.StringIO(newline='')
    writer = csv.writer(stream, lineterminator='\n')
    writer.writerow(['timestamp', 'sensor_alpha', 'sensor_beta', 'sensor_gamma', 'notes'])
    writer.writerows(records)
    return stream.getvalue()


def test_z_script_executes_on_derived_inputs_and_opens_files_concurrently():
    script = find_processing_script()
    token = secrets.token_hex(8)
    base = secrets.randbelow(5000) + 50
    sources = {
        'site_1': [
            ('2024-03-01T10:10:00Z', str(base + 4), str(base + 14), '', 'late ' + token),
            ('2024-03-01T10:00:00Z', str(base), str(base + 10), str(base + 20), 'first\nline ' + token),
            ('2024-03-01T10:05:00Z', str(base + 2), '', str(base + 24), 'middle ' + token),
            ('2024-03-01T10:15:00Z', str(base + 8), str(base + 18), str(base + 28), 'last ' + token),
        ],
        'site_2': [
            ('2024-04-02T09:05:00Z', str(base * 2 + 2), str(base * 2 + 12), str(base * 2 + 22), 's2 later ' + token),
            ('2024-04-02T09:00:00Z', str(base * 2), str(base * 2 + 10), str(base * 2 + 20), 's2\nfirst ' + token),
        ],
        'site_3': [
            ('2024-05-03T08:00:00Z', '1.25', '2.5', '3.75', 'site three ' + token),
        ],
        'site_4': [],
    }

    input_dir = Path('/home/user/input_data')
    output = Path(OUTPUT_FILE)
    backup_root = Path(tempfile.mkdtemp(prefix='pipeline_verify_'))
    backup_input = backup_root / 'input_data'
    had_output = output.exists()
    output_bytes = output.read_bytes() if had_output else None
    proc = None

    try:
        input_dir.rename(backup_input)
        input_dir.mkdir(parents=True)
        payloads = {}
        for site, records in sources.items():
            fifo = input_dir / f'{site}.csv'
            os.mkfifo(fifo, 0o666)
            payloads[fifo] = csv_text(records)

        if output.exists():
            output.unlink()

        opened = 0
        lock = threading.Lock()
        release = threading.Event()

        def writer(path, payload):
            nonlocal opened
            with open(path, 'w', encoding='utf-8', newline='') as f:
                with lock:
                    opened += 1
                    if opened >= 2:
                        release.set()
                if not release.wait(12):
                    return
                f.write(payload)
                f.flush()

        threads = []
        for path, payload in payloads.items():
            thread = threading.Thread(target=writer, args=(path, payload), daemon=True)
            thread.start()
            threads.append(thread)

        proc = subprocess.Popen(
            command_for(script), cwd=str(script.parent), stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, start_new_session=True
        )
        try:
            stdout, stderr = proc.communicate(timeout=20)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
            stdout, stderr = proc.communicate()
            pytest.fail("Processing script timed out; files were not opened concurrently")

        assert proc.returncode == 0, f"Processing script failed. stdout={stdout!r} stderr={stderr!r}"
        assert opened >= 2, "The script did not process input files concurrently"
        assert output.is_file(), "Executing the processing script did not create the requested output"
        assert_complete_output(str(output), sources)
    finally:
        if proc is not None and proc.poll() is None:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.wait()
        if input_dir.exists():
            shutil.rmtree(input_dir, ignore_errors=True)
        if backup_input.exists():
            backup_input.rename(input_dir)
        output.parent.mkdir(parents=True, exist_ok=True)
        if had_output:
            output.write_bytes(output_bytes)
        elif output.exists():
            output.unlink()
        shutil.rmtree(backup_root, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
