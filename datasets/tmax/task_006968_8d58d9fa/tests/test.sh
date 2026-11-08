#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import resource
import subprocess
from collections import defaultdict, deque

SCRIPT_PATH = '/home/user/etl_pipeline.py'
INPUT_PATH = '/home/user/inputs/auth_logs.csv'
OUTPUT_PATH = '/home/user/outputs/processed_logs.csv'


def run_pipeline(memory_limit_mb=None, timeout=120):
    def set_limit():
        if memory_limit_mb is not None:
            limit = memory_limit_mb * 1024 * 1024
            resource.setrlimit(resource.RLIMIT_AS, (limit, limit))

    result = subprocess.run(
        ['python3', SCRIPT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        preexec_fn=set_limit if memory_limit_mb is not None else None,
    )
    assert result.returncode == 0, (
        f'Pipeline exited with status {result.returncode}. '
        f'stdout={result.stdout.decode("utf-8", "replace")!r}, '
        f'stderr={result.stderr.decode("utf-8", "replace")!r}'
    )
    assert os.path.isfile(OUTPUT_PATH), 'Pipeline did not create the output file.'


def read_utf8_output():
    try:
        with open(OUTPUT_PATH, 'r', encoding='utf-8', newline='') as f:
            return list(csv.reader(f))
    except UnicodeDecodeError as exc:
        raise AssertionError(f'The output file is not properly UTF-8 encoded: {exc}')


def expected_rows(data):
    result = [['timestamp', 'masked_ip', 'masked_email', 'rolling_count']]
    windows = defaultdict(deque)
    for timestamp_text, ip, email in data:
        timestamp = int(timestamp_text)
        masked_ip = ip.rsplit('.', 1)[0] + '.XXX'
        local, domain = email.split('@', 1)
        masked_email = local[0] + '***@' + domain
        window = windows[masked_ip]
        while window and timestamp - window[0] > 60:
            window.popleft()
        window.append(timestamp)
        result.append([timestamp_text, masked_ip, masked_email, str(len(window))])
    return result


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f'The script {SCRIPT_PATH} does not exist.'


def test_output_file_exists():
    assert os.path.isfile(OUTPUT_PATH), f'The output file {OUTPUT_PATH} does not exist.'


def test_output_content_and_encoding():
    try:
        with open(OUTPUT_PATH, 'r', encoding='utf-8') as f:
            reader = csv.reader(f)
            actual_rows = list(reader)
    except UnicodeDecodeError:
        assert False, f'The output file {OUTPUT_PATH} is not properly utf-8 encoded.'
    except Exception as e:
        assert False, f'Failed to read {OUTPUT_PATH}: {e}'

    expected = [
        ['timestamp', 'masked_ip', 'masked_email', 'rolling_count'],
        ['1700000000', '192.168.1.XXX', 'a***@example.com', '1'],
        ['1700000010', '192.168.1.XXX', 'b***@test.org', '2'],
        ['1700000030', '192.168.1.XXX', 'a***@example.com', '3'],
        ['1700000050', '10.0.0.XXX', 'c***@foo.net', '1'],
        ['1700000070', '192.168.1.XXX', 'd***@bar.com', '3'],
        ['1700000100', '192.168.1.XXX', 'e***@baz.com', '2'],
    ]

    assert len(actual_rows) == len(expected), f'Expected {len(expected)} rows, but got {len(actual_rows)}.'
    for i, (actual, wanted) in enumerate(zip(actual_rows, expected)):
        assert actual == wanted, f'Row {i} mismatch. Expected {wanted}, got {actual}.'


def test_pipeline_executes_on_derived_cp1252_case():
    data = [
        ['1800000000', '1.2.3.4', 'Élodie@exämple.com'],
        ['1800000001', '1.2.3.250', 'bravo@test.org'],
        ['1800000060', '1.2.3.99', 'carol@example.net'],
        ['1800000061', '1.2.3.7', 'delta@example.net'],
        ['1800000062', '9.8.7.6', 'françois@café.example'],
        ['1800000122', '9.8.7.200', 'golf@café.example'],
        ['1800000123', '9.8.7.1', 'hotel@café.example'],
    ]
    with open(INPUT_PATH, 'w', encoding='cp1252', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['timestamp', 'ip_address', 'email'])
        writer.writerows(data)

    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    run_pipeline()
    assert read_utf8_output() == expected_rows(data)


def test_pipeline_streams_large_input_under_memory_limit():
    row_count = 700000
    base = 1900000000
    with open(INPUT_PATH, 'w', encoding='cp1252', newline='') as f:
        f.write('timestamp,ip_address,email\r\n')
        for i in range(row_count):
            f.write(f'{base + i},172.20.5.{(i % 250) + 1},user{i}@café.example\r\n')

    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    run_pipeline(memory_limit_mb=64, timeout=120)

    try:
        with open(OUTPUT_PATH, 'r', encoding='utf-8', newline='') as f:
            reader = csv.reader(f)
            assert next(reader) == ['timestamp', 'masked_ip', 'masked_email', 'rolling_count']
            count = 0
            for i, row in enumerate(reader):
                expected = [
                    str(base + i),
                    '172.20.5.XXX',
                    'u***@café.example',
                    str(min(i + 1, 61)),
                ]
                assert row == expected, f'Large-input row {i} mismatch: expected {expected}, got {row}'
                count += 1
            assert count == row_count, f'Expected {row_count} data rows, got {count}'
    except UnicodeDecodeError as exc:
        raise AssertionError(f'The large output is not properly UTF-8 encoded: {exc}')
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
