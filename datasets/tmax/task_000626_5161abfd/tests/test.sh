#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import os
import pathlib
import subprocess

import pytest

HOME = pathlib.Path('/home/user')
SCRIPT = HOME / 'run_etl.sh'
SOURCE = HOME / 'etl.cpp'
BINARY = HOME / 'etl_bin'
TEMP_CSV = HOME / 'data/temp.csv'
HUMIDITY_CSV = HOME / 'data/humidity.csv'
OUTPUT = HOME / 'output/merged.csv'


def run_checked(command, *, user=None, timeout=30):
    if user is not None:
        command = ['runuser', '-u', user, '--'] + [str(x) for x in command]
    return subprocess.run(
        [str(x) for x in command],
        cwd=str(HOME),
        env={**os.environ, 'HOME': str(HOME)},
        capture_output=True,
        text=True,
        timeout=timeout,
        check=True,
    )


def remove_artifact(path):
    try:
        path.unlink()
    except FileNotFoundError:
        pass


def read_output_lines():
    assert OUTPUT.is_file(), f'{OUTPUT} does not exist after running the ETL pipeline.'
    try:
        content = OUTPUT.read_text(encoding='utf-8')
    except UnicodeDecodeError:
        pytest.fail(f'{OUTPUT} is not properly encoded in UTF-8.')
    return [line.strip() for line in content.strip().splitlines() if line.strip()]


def assert_output(expected_lines):
    actual_lines = read_output_lines()
    assert actual_lines == expected_lines, (
        f'Content of {OUTPUT} does not match the expected inner join result.\n'
        f'Expected:\n{expected_lines}\nActual:\n{actual_lines}'
    )


def iso_epoch(value):
    return int(datetime.datetime.fromisoformat(value.replace('Z', '+00:00')).timestamp())


def test_run_etl_script_exists_and_executable():
    assert SCRIPT.is_file(), f'{SCRIPT} does not exist.'
    assert os.access(SCRIPT, os.X_OK), f'{SCRIPT} is not executable.'


def test_etl_cpp_exists():
    assert SOURCE.is_file(), f'{SOURCE} does not exist.'


def test_user_crontab_entry_exists():
    try:
        result = subprocess.run(
            ['crontab', '-u', 'user', '-l'],
            capture_output=True,
            text=True,
            timeout=10,
            check=True,
        )
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
        pytest.fail("Failed to read account 'user' crontab. Has it been set up?")

    found = False
    for raw_line in result.stdout.splitlines():
        line = raw_line.strip()
        if not line or line.startswith('#'):
            continue
        fields = line.split(None, 5)
        if (
            len(fields) == 6
            and fields[:5] == ['*/15', '*', '*', '*', '*']
            and '/home/user/run_etl.sh' in fields[5]
        ):
            found = True
            break

    assert found, (
        "Crontab entry for /home/user/run_etl.sh running every 15 minutes "
        "was not found in account 'user's crontab."
    )


def test_pipeline_executes_and_handles_changed_inputs():
    # Force the submitted wrapper to compile and run rather than accepting a
    # pre-created output or binary, then retain the original fixed-result check.
    remove_artifact(BINARY)
    remove_artifact(OUTPUT)
    try:
        run_checked([SCRIPT], user='user', timeout=45)
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
        pytest.fail(f'run_etl.sh failed on the supplied input: {exc}')

    original_expected = [
        'timestamp,temperature,humidity',
        '1697107200,22.4,45.2',
        '1697107500,22.5,46.1',
        '1697107800,22.6,45.8',
        '1697108700,23.4,48.5',
    ]
    assert_output(original_expected)

    temp_backup = TEMP_CSV.read_bytes()
    humidity_backup = HUMIDITY_CSV.read_bytes()
    try:
        humidity_rows = [
            ('2024-02-03T04:07:00Z', '71.5'),
            ('2024-02-03T04:05:00Z', '70.1'),
            ('2024-02-03T04:10:00Z', '99.9'),
            ('2024-02-03T04:06:00Z', '69.8'),
        ]
        temp_rows = [
            (iso_epoch('2024-02-03T04:06:00Z'), '-3.25'),
            (iso_epoch('2024-02-03T04:08:00Z'), '8.0'),
            (iso_epoch('2024-02-03T04:05:00Z'), '1.125'),
            (iso_epoch('2024-02-03T04:07:00Z'), '2.5'),
        ]

        temp_text = 'timestamp,temperature\n' + ''.join(
            f'{timestamp},{temperature}\n' for timestamp, temperature in temp_rows
        )
        TEMP_CSV.write_bytes(temp_text.encode('utf-16le'))

        humidity_text = 'timestamp,humidity\n' + ''.join(
            f'{timestamp},{humidity}\n' for timestamp, humidity in humidity_rows
        )
        HUMIDITY_CSV.write_text(humidity_text, encoding='utf-8')

        humidity_by_epoch = {iso_epoch(ts): value for ts, value in humidity_rows}
        joined = sorted(
            (timestamp, temperature, humidity_by_epoch[timestamp])
            for timestamp, temperature in temp_rows
            if timestamp in humidity_by_epoch
        )
        dynamic_expected = ['timestamp,temperature,humidity'] + [
            f'{timestamp},{temperature},{humidity}'
            for timestamp, temperature, humidity in joined
        ]

        # Exercise the submitted wrapper on unseen data and force recompilation.
        remove_artifact(BINARY)
        remove_artifact(OUTPUT)
        try:
            run_checked([SCRIPT], user='user', timeout=45)
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
            pytest.fail(f'run_etl.sh failed on changed input: {exc}')
        assert BINARY.is_file(), 'run_etl.sh did not create /home/user/etl_bin.'
        assert os.access(BINARY, os.X_OK), '/home/user/etl_bin is not executable.'
        assert_output(dynamic_expected)

        # Independently compile etl.cpp and execute that compiled artifact, so a
        # wrapper that merely manufactures the expected CSV cannot pass.
        verified_binary = pathlib.Path('/tmp/verified_etl_bin')
        remove_artifact(verified_binary)
        try:
            run_checked(
                ['g++', '-std=c++17', '-O2', str(SOURCE), '-o', str(verified_binary)],
                timeout=45,
            )
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
            pytest.fail(f'etl.cpp did not compile as C++17: {exc}')

        remove_artifact(OUTPUT)
        try:
            run_checked([verified_binary], user='user', timeout=30)
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
            pytest.fail(f'The independently compiled etl.cpp failed: {exc}')
        assert_output(dynamic_expected)
    finally:
        TEMP_CSV.write_bytes(temp_backup)
        HUMIDITY_CSV.write_bytes(humidity_backup)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
