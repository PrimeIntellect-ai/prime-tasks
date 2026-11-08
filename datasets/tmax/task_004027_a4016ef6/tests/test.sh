#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import stat
import subprocess
import urllib.request

RAW_DIR = '/home/user/data/raw_configs'
CSV_PATH = '/home/user/data/configs.csv'
DAT_PATH = '/home/user/data/configs.dat'
COMPRESS_PATH = '/home/user/scripts/compress.py'
DECOMPRESS_PATH = '/home/user/scripts/decompress.py'


def reference_lines():
    assert os.path.exists(RAW_DIR), f"Directory {RAW_DIR} does not exist."
    records = []
    for fname in os.listdir(RAW_DIR):
        if fname.endswith('.json'):
            with open(os.path.join(RAW_DIR, fname), 'r') as f:
                data = json.load(f)
            records.append({
                'timestamp': int(data['timestamp']),
                'service': data['service'],
                'rate_limit': data['config']['rate_limit'],
                'timeout': data['config']['timeout'],
            })
    records.sort(key=lambda x: x['timestamp'])
    return [
        f"{r['timestamp']},{r['service']},{r['rate_limit']},{r['timeout']}"
        for r in records
    ]


def assert_regular_file(path):
    assert os.path.exists(path), f"Required file {path} does not exist."
    assert stat.S_ISREG(os.lstat(path).st_mode), f"Required path {path} is not a regular file."


def run_script(path):
    return subprocess.run(
        ['python3', path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
        check=True,
    )


def test_compression_size():
    dat_path = '/home/user/data/configs.dat'
    assert os.path.exists(dat_path), f"File {dat_path} does not exist. Did you run the compression script?"

    size = os.path.getsize(dat_path)
    threshold = 85000
    assert size < threshold, f"Compression size metric failed: {dat_path} is {size} bytes, which is not less than the threshold of {threshold} bytes."


def test_required_conversion_and_compression_artifacts():
    assert_regular_file(CSV_PATH)
    assert_regular_file(COMPRESS_PATH)
    assert_regular_file(DECOMPRESS_PATH)

    expected_lines = reference_lines()
    with open(CSV_PATH, 'rb') as f:
        original_csv = f.read()

    try:
        decoded_csv = original_csv.decode('utf-8')
    except UnicodeDecodeError as e:
        assert False, f"{CSV_PATH} is not valid UTF-8 CSV data: {e}"

    csv_lines = [line.strip() for line in decoded_csv.split('\n') if line.strip()]
    has_header = bool(csv_lines and csv_lines[0] == 'timestamp,service,rate_limit,timeout')
    data_lines = csv_lines[1:] if has_header else csv_lines
    assert data_lines == expected_lines, f"{CSV_PATH} does not contain the complete chronologically sorted data derived from the raw JSON files."

    token = secrets.token_hex(8)
    hidden_raw = f"{RAW_DIR}.__verifier_hidden_{token}"
    hidden_csv = f"{CSV_PATH}.__verifier_hidden_{token}"

    rng = secrets.SystemRandom()
    selected = sorted(rng.sample(expected_lines, 11), key=lambda line: int(line.split(',', 1)[0]))
    probe_lines = (['timestamp,service,rate_limit,timeout'] if has_header else []) + selected
    probe_text = '\n'.join(probe_lines)
    if original_csv.endswith(b'\n'):
        probe_text += '\n'
    probe_csv = probe_text.encode('utf-8')

    os.replace(RAW_DIR, hidden_raw)
    try:
        # Exercise the compressor on an unpredictable valid CSV while the raw
        # JSON source is unavailable, proving that it consumes configs.csv.
        with open(CSV_PATH, 'wb') as f:
            f.write(probe_csv)
        if os.path.lexists(DAT_PATH):
            os.unlink(DAT_PATH)
        run_script(COMPRESS_PATH)
        assert_regular_file(DAT_PATH)
        assert os.path.getsize(DAT_PATH) > 0, f"{DAT_PATH} is empty."
        assert os.path.getsize(DAT_PATH) < 85000, f"Probe compression exceeded the 85,000-byte limit."

        # Hide every textual source before decompression so the probe output
        # must be recovered from configs.dat rather than read from CSV or JSON.
        os.replace(CSV_PATH, hidden_csv)
        probe_result = run_script(DECOMPRESS_PATH)
        assert probe_result.stdout == probe_csv, (
            "decompress.py did not reproduce the probe CSV exactly from configs.dat.\n"
            f"stderr: {probe_result.stderr.decode('utf-8', errors='replace')}"
        )
        os.replace(hidden_csv, CSV_PATH)

        # Restore the required CSV and produce the final compressed artifact.
        with open(CSV_PATH, 'wb') as f:
            f.write(original_csv)
        os.unlink(DAT_PATH)
        run_script(COMPRESS_PATH)
        assert_regular_file(DAT_PATH)
        size = os.path.getsize(DAT_PATH)
        assert size < 85000, f"Compression size metric failed: {DAT_PATH} is {size} bytes, which is not less than the threshold of 85000 bytes."

        os.replace(CSV_PATH, hidden_csv)
        final_result = run_script(DECOMPRESS_PATH)
        assert final_result.stdout == original_csv, (
            "decompress.py did not restore the exact contents of configs.csv from configs.dat.\n"
            f"stderr: {final_result.stderr.decode('utf-8', errors='replace')}"
        )
        os.replace(hidden_csv, CSV_PATH)
    finally:
        if os.path.exists(hidden_csv):
            os.replace(hidden_csv, CSV_PATH)
        with open(CSV_PATH, 'wb') as f:
            f.write(original_csv)
        if os.path.exists(hidden_raw):
            os.replace(hidden_raw, RAW_DIR)


def test_data_integrity():
    raw_configs_dir = '/home/user/data/raw_configs'
    assert os.path.exists(raw_configs_dir), f"Directory {raw_configs_dir} does not exist."

    # Generate reference CSV data from raw JSON files
    records = []
    for fname in os.listdir(raw_configs_dir):
        if fname.endswith('.json'):
            with open(os.path.join(raw_configs_dir, fname), 'r') as f:
                data = json.load(f)
                records.append({
                    'timestamp': int(data['timestamp']),
                    'service': data['service'],
                    'rate_limit': data['config']['rate_limit'],
                    'timeout': data['config']['timeout']
                })

    # Sort chronologically by timestamp
    records.sort(key=lambda x: x['timestamp'])

    expected_lines = []
    for r in records:
        expected_lines.append(f"{r['timestamp']},{r['service']},{r['rate_limit']},{r['timeout']}")

    # Remove any preloaded response so Flask must process the final artifact.
    cleared = subprocess.run(
        ['redis-cli', 'DEL', 'history'],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )
    assert cleared.returncode == 0, f"Failed to clear Redis history cache: {cleared.stderr.decode('utf-8', errors='replace')}"

    # Fetch from API
    url = "http://localhost:8080/history"
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=5) as response:
            actual_csv = response.read().decode('utf-8')
    except Exception as e:
        assert False, f"Failed to fetch data from {url}. Are Nginx and Flask running and configured correctly? Error: {e}"

    actual_lines = [line.strip() for line in actual_csv.split('\n') if line.strip()]

    # Tolerate if the user included a header row
    if actual_lines and actual_lines[0] == "timestamp,service,rate_limit,timeout":
        actual_lines = actual_lines[1:]

    assert len(actual_lines) == len(expected_lines), f"Data integrity metric failed: Expected {len(expected_lines)} rows, but got {len(actual_lines)} rows from the API."

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, f"Data integrity metric failed at row {i+1}:\nExpected: {expected}\nActual:   {actual}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
