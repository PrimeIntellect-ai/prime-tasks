#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import sqlite3
import subprocess
import tempfile
from pathlib import Path

import pytest

HOME = Path('/home/user')


def run(cmd, *, cwd=None, timeout=30):
    return subprocess.run(
        cmd,
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        check=True,
    )


def compile_c(source, output, extra=()):
    if os.path.exists(output):
        os.unlink(output)
    run(['gcc', source, '-o', output, *extra], timeout=60)
    assert os.path.isfile(output), f'Compilation did not create {output}'
    assert os.access(output, os.X_OK), f'{output} is not executable'
    with open(output, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f'{output} is not an ELF executable'


def trace_program(executable, cwd, trace_path, timeout=60):
    result = run(
        ['strace', '-f', '-e', 'trace=open,openat', '-o', trace_path, executable],
        cwd=cwd,
        timeout=timeout,
    )
    trace = Path(trace_path).read_text(errors='replace')
    calls = re.findall(r'(?:^|\s)(open|openat)\([^\n]*?"([^"]+)"', trace, re.MULTILINE)
    return result.stdout, calls


def zone_calls(calls, suffix):
    return [(call, path) for call, path in calls if path.endswith(suffix)]


def create_profile_db(directory):
    db_path = Path(directory) / 'sensor_data.db'
    conn = sqlite3.connect(db_path)
    conn.execute('CREATE TABLE sensors (id INTEGER PRIMARY KEY, value REAL, timestamp TEXT, timezone TEXT)')
    values = []
    for i in range(1, 101):
        value = float((i % 13) - 6) + 0.25
        timezone = 'America/New_York' if i <= 50 else 'Europe/London'
        values.append(value)
        conn.execute(
            'INSERT INTO sensors VALUES (?, ?, ?, ?)',
            (i, value, '2023-10-01 10:00:00', timezone),
        )
    conn.commit()
    conn.close()
    return sum(values)


def assert_profiled_analyzer(executable, directory, expected_sum, tag):
    trace_path = str(Path(directory) / f'{tag}.trace')
    stdout, calls = trace_program(executable, directory, trace_path)
    assert stdout.strip() == f'Total sum: {expected_sum:.2f}', (
        f'{executable} produced incorrect output on a verifier-created database: {stdout!r}'
    )

    ny = zone_calls(calls, '/America/New_York')
    london = zone_calls(calls, '/Europe/London')
    assert 1 <= len(ny) <= 3, (
        f'{executable} should load America/New_York once per consecutive timezone group; '
        f'observed {len(ny)} opens.'
    )
    assert 1 <= len(london) <= 3, (
        f'{executable} should load Europe/London once per consecutive timezone group; '
        f'observed {len(london)} opens.'
    )


def test_database_recovered():
    db_path = HOME / 'sensor_data.db'
    assert db_path.is_file(), f'Database file {db_path} does not exist.'

    conn = sqlite3.connect(db_path)
    try:
        cursor = conn.cursor()
        cursor.execute('SELECT COUNT(*), MIN(id), MAX(id), SUM(value) FROM sensors')
        count, min_id, max_id, total_sum = cursor.fetchone()
        assert count == 50005, f"Expected exactly 50005 rows in 'sensors' table, but found {count}."
        assert (min_id, max_id) == (1, 50005), f'Expected IDs 1 through 50005, got {min_id} through {max_id}.'
        expected_sum = 500058.60
        assert total_sum is not None, 'The sum of values is NULL.'
        assert abs(total_sum - expected_sum) < 0.01, (
            f'Expected total sum of approximately {expected_sum}, but got {total_sum}.'
        )

        expected_first = [
            (1, 10.5, '2023-10-01 10:00:00', 'America/New_York'),
            (2, 12.0, '2023-10-01 10:05:00', 'America/New_York'),
            (3, 15.2, '2023-10-01 10:10:00', 'America/New_York'),
            (4, 11.1, '2023-10-01 10:15:00', 'America/New_York'),
            (5, 9.8, '2023-10-01 10:20:00', 'America/New_York'),
        ]
        cursor.execute('SELECT id, value, timestamp, timezone FROM sensors WHERE id <= 5 ORDER BY id')
        assert cursor.fetchall() == expected_first, 'The backup and initial WAL records were not faithfully recovered.'

        cursor.execute('''
            SELECT COUNT(*) FROM sensors
            WHERE id BETWEEN 6 AND 50005
              AND value = 10.0
              AND timestamp = '2023-10-01 10:25:00'
              AND timezone = 'America/New_York'
        ''')
        assert cursor.fetchone()[0] == 50000, 'Not all remaining WAL records were faithfully replayed.'
    finally:
        conn.close()


def test_bottleneck_txt():
    path = HOME / 'bottleneck.txt'
    assert path.is_file(), f'File {path} does not exist.'
    raw = path.read_text()
    assert len(raw.splitlines()) == 1, f'{path} must contain exactly one line.'
    content = raw.strip()
    pattern = r'^(open|openat):.*/America/New_York$'
    assert re.match(pattern, content), (
        f"Contents of {path} ('{content}') do not match the expected format "
        "'<syscall>:<filepath>' for the timezone file bottleneck."
    )


def test_mre_c_executes_and_reproduces_bottleneck():
    path = HOME / 'mre.c'
    assert path.is_file(), f'File {path} does not exist.'
    content = path.read_text()

    assert 'setenv' in content, f"{path} is missing the 'setenv' call."
    assert 'tzset' in content, f"{path} is missing the 'tzset' call."
    assert 'sqlite3' not in content, f'{path} should not contain any SQLite code.'
    assert re.search(r'(for|while)\s*\(', content), f'{path} does not appear to contain a loop.'
    assert '10000' in content, f'{path} should loop for 10,000 iterations.'

    executable = '/tmp/verified_mre'
    compile_c(str(path), executable)
    stdout, calls = trace_program(executable, '/tmp', '/tmp/verified_mre.trace', timeout=60)

    repeated = zone_calls(calls, '/America/New_York')
    assert len(repeated) >= 1000, (
        'The compiled MRE did not reproduce the redundant timezone-file operation '
        f'inside its loop; observed only {len(repeated)} matching opens.'
    )

    reported_call, reported_path = (HOME / 'bottleneck.txt').read_text().strip().split(':', 1)
    assert (reported_call, reported_path) in repeated, (
        'bottleneck.txt does not identify the syscall/path actually observed while tracing the MRE.'
    )


def test_analyzer_c_fixed_and_executables_profiled():
    source = HOME / 'analyzer.c'
    assert source.is_file(), f'File {source} does not exist.'
    content = source.read_text()

    assert 'strcmp' in content or 'strncmp' in content or '!= NULL' in content or 'strcpy' in content, (
        f'{source} does not appear to conditionally check the timezone before updating it.'
    )
    assert 'setenv' in content and 'tzset' in content, 'The timezone handling sequence was removed rather than cached.'

    submitted = HOME / 'analyzer'
    assert submitted.is_file(), f'Compiled analyzer {submitted} does not exist.'
    assert os.access(submitted, os.X_OK), f'{submitted} is not executable.'
    with open(submitted, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f'{submitted} is not an ELF executable.'

    rebuilt = '/tmp/verified_analyzer'
    compile_c(str(source), rebuilt, ['-lsqlite3'])

    with tempfile.TemporaryDirectory(prefix='analyzer-profile-') as directory:
        expected_sum = create_profile_db(directory)
        assert_profiled_analyzer(str(submitted), directory, expected_sum, 'submitted')
        assert_profiled_analyzer(rebuilt, directory, expected_sum, 'rebuilt')

    stdout, calls = trace_program(str(submitted), str(HOME), '/tmp/submitted-main.trace', timeout=60)
    assert stdout.strip() == 'Total sum: 500058.60', f'Submitted analyzer output was incorrect: {stdout!r}'
    main_zone_opens = zone_calls(calls, '/America/New_York')
    assert 1 <= len(main_zone_opens) <= 5, (
        f'The submitted analyzer still redundantly opens the timezone file: {len(main_zone_opens)} opens observed.'
    )


def test_output_txt():
    path = HOME / 'output.txt'
    assert path.is_file(), f'File {path} does not exist.'
    content = path.read_text().strip()
    assert '500058.6' in content, f"File {path} does not contain the correct expected sum. Content was: '{content}'"
    assert content == 'Total sum: 500058.60', f'{path} is not the exact standard output of the corrected analyzer.'

    actual = run([str(HOME / 'analyzer')], cwd=str(HOME), timeout=60).stdout.strip()
    assert content == actual, 'output.txt does not match the current compiled analyzer standard output.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
