#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import re
import stat
import subprocess
import uuid
from collections import Counter


def read_csv(path):
    with open(path, newline='') as f:
        return [row for row in csv.reader(f) if row]


def run_pipeline():
    result = subprocess.run(
        ['/bin/bash', '/home/user/pipeline.sh'],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f'Executing pipeline.sh failed with return code {result.returncode}\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )


def test_01_scripts_exist():
    paths = [
        '/home/user/extract.py',
        '/home/user/compute.py',
        '/home/user/pipeline.sh',
    ]
    for path in paths:
        assert os.path.exists(path), f'{path} is missing.'
        st = os.stat(path)
        assert bool(st.st_mode & stat.S_IXUSR), f'{path} is not executable.'

    # Both Python stages must at least be valid Python programs.
    result = subprocess.run(
        ['python3', '-m', 'py_compile', '/home/user/extract.py', '/home/user/compute.py'],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert result.returncode == 0, f'Python script syntax error:\n{result.stderr}'

    with open('/home/user/pipeline.sh') as f:
        pipeline = f.read()
    assert 'extract.py' in pipeline, 'pipeline.sh does not use extract.py.'
    assert 'compute.py' in pipeline, 'pipeline.sh does not use compute.py.'


def test_02_cron_file():
    cron_path = '/home/user/schedule.cron'
    assert os.path.exists(cron_path), f'{cron_path} is missing.'

    with open(cron_path, 'r') as f:
        raw = f.read()
        content = raw.strip()

    valid_prefixes = ['*/15 * * * *', '0,15,30,45 * * * *']
    has_valid_prefix = any(content.startswith(prefix) for prefix in valid_prefixes)
    assert has_valid_prefix, f'Cron schedule does not match every 15 minutes. Found: {content}'
    assert '/home/user/pipeline.sh' in content, 'Cron file does not contain the pipeline script path.'
    assert len(raw.splitlines()) == 1, 'schedule.cron must contain exactly one line.'
    assert re.search(r'/bin/bash\s+/home/user/pipeline\.sh(?:\s|$)', content), (
        'Cron entry must invoke /home/user/pipeline.sh explicitly with /bin/bash.'
    )


def test_03_original_pipeline_execution_and_output():
    incoming_dir = '/home/user/incoming_logs'
    archive_dir = '/home/user/archive'
    output_csv = '/home/user/output_metrics.csv'

    if os.path.exists(os.path.join(incoming_dir, 'day1.log')):
        run_pipeline()

    assert os.path.exists(output_csv), f'{output_csv} was not created.'
    rows = read_csv(output_csv)
    assert len(rows) > 0, 'output_metrics.csv is empty.'
    assert rows[0] == ['route_id', 'distance'], (
        f"Incorrect CSV header. Expected ['route_id', 'distance'], got {rows[0]}"
    )

    expected_data = [
        ['alpha-01', '5.00'],
        ['beta-02', '5.00'],
        ['delta-04', '12.00'],
    ]
    data_rows = rows[1:]
    assert data_rows == expected_data, f'CSV data mismatch.\nExpected:\n{expected_data}\nGot:\n{data_rows}'

    assert not os.path.exists(os.path.join(incoming_dir, 'day1.log')), (
        'day1.log was not removed from incoming_logs.'
    )
    assert os.path.exists(os.path.join(archive_dir, 'day1.log')), (
        'day1.log was not moved to archive.'
    )


def test_04_pipeline_on_generated_inputs_and_append_behavior():
    incoming_dir = '/home/user/incoming_logs'
    archive_dir = '/home/user/archive'
    output_csv = '/home/user/output_metrics.csv'
    os.makedirs(incoming_dir, exist_ok=True)
    os.makedirs(archive_dir, exist_ok=True)

    # Isolate this behavioral test from the fixed fixture and any pre-existing output.
    for name in os.listdir(incoming_dir):
        if name.endswith('.log'):
            os.unlink(os.path.join(incoming_dir, name))
    if os.path.exists(output_csv):
        os.unlink(output_csv)

    token = uuid.uuid4().hex[:12]
    routes = [f'rt-{token}-a', f'rt-{token}-b', f'rt-{token}-c', f'rt-{token}-d']
    first_names = [f'generated-{token}-one.log', f'generated-{token}-two.log']

    with open(os.path.join(incoming_dir, first_names[0]), 'w') as f:
        f.write(
            f'prefix [2040-01-01T00:00:00] Route {routes[0]}: Departed from '
            f'(X: -7.25, Y: 3.5) -> Arrived at (X: 4.75, Y: -1.5) | Status: SUCCESS trailing text\n'
        )
        f.write(
            f'[2040-01-01T00:01:00] Route ignored-{token}-failed: Departed from '
            f'(X: 0.0, Y: 0.0) -> Arrived at (X: 99.0, Y: 99.0) | Status: FAILED\n'
        )
        f.write(f'[2040-01-01T00:02:00] Route ignored-{token}-bad: no coordinates | Status: SUCCESS\n')

    with open(os.path.join(incoming_dir, first_names[1]), 'w') as f:
        f.write(
            f'[2040-01-02T12:00:00] Route {routes[1]}: Departed from '
            f'(X: 101.2, Y: -44.8) -> Arrived at (X: 98.2, Y: -40.8) | Status: SUCCESS\n'
        )
        f.write('unrelated corrupted text\n')
        f.write(
            f'[2040-01-02T12:01:00] Route {routes[2]}: Departed from '
            f'(X: -2.5, Y: -2.5) -> Arrived at (X: -2.5, Y: 8.75) | Status: SUCCESS\n'
        )

    run_pipeline()

    assert os.path.exists(output_csv), 'Generated-input run did not create output_metrics.csv.'
    rows = read_csv(output_csv)
    assert rows and rows[0] == ['route_id', 'distance'], 'Generated-input CSV has an incorrect header.'
    expected_first = [
        [routes[0], f'{math.hypot(4.75 - (-7.25), -1.5 - 3.5):.2f}'],
        [routes[1], f'{math.hypot(98.2 - 101.2, -40.8 - (-44.8)):.2f}'],
        [routes[2], f'{math.hypot(-2.5 - (-2.5), 8.75 - (-2.5)):.2f}'],
    ]
    assert Counter(map(tuple, rows[1:])) == Counter(map(tuple, expected_first)), (
        f'Pipeline failed on generated records. Expected {expected_first}, got {rows[1:]}'
    )
    for name in first_names:
        assert not os.path.exists(os.path.join(incoming_dir, name)), f'{name} was not removed from incoming.'
        assert os.path.exists(os.path.join(archive_dir, name)), f'{name} was not moved to archive.'

    # A second invocation must append one new result without repeating the header.
    second_name = f'generated-{token}-three.log'
    with open(os.path.join(incoming_dir, second_name), 'w') as f:
        f.write(
            f'[2040-01-03T09:00:00] Route {routes[3]}: Departed from '
            f'(X: 6.125, Y: 9.5) -> Arrived at (X: -1.875, Y: -5.5) | Status: SUCCESS\n'
        )

    run_pipeline()
    rows = read_csv(output_csv)
    expected_all = expected_first + [[routes[3], f'{math.hypot(-1.875 - 6.125, -5.5 - 9.5):.2f}']]
    assert rows.count(['route_id', 'distance']) == 1, 'CSV header was repeated when appending.'
    assert Counter(map(tuple, rows[1:])) == Counter(map(tuple, expected_all)), (
        f'Second run did not append correctly. Expected {expected_all}, got {rows[1:]}'
    )
    assert not os.path.exists(os.path.join(incoming_dir, second_name)), (
        'Second generated log was not removed from incoming.'
    )
    assert os.path.exists(os.path.join(archive_dir, second_name)), (
        'Second generated log was not moved to archive.'
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
