#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import os
import re
import secrets
import shutil
import stat
import subprocess
import time
from pathlib import Path

import pytest

HOME = Path('/home/user')
LOG_DIR = HOME / 'logs'
ARCHIVE = HOME / 'critical_archive.log'
FILTER_SRC = HOME / 'log_filter.cpp'
FILTER_BIN = HOME / 'log_filter'
SCRIPT = HOME / 'process_logs.sh'


def run_filter(executable, lines):
    payload = ''.join(line + '\n' for line in lines)
    result = subprocess.run(
        [str(executable)], input=payload, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=10
    )
    assert result.returncode == 0, result.stderr
    return result.stdout.splitlines()


def test_complete_pipeline():
    # Preserve all original final-state assertions.
    assert ARCHIVE.is_file(), f'The archive file {ARCHIVE} does not exist.'
    expected_fixed = {
        '[2023-01-01 10:05:00] [ERROR] [192.168.10.XXX] Database connection failed',
        '[2023-01-01 10:10:00] [CRITICAL] [172.16.0.XXX] Out of memory',
        '[2023-01-02 11:05:00] [ERROR] [8.8.8.XXX] DNS resolution failed'
    }
    with ARCHIVE.open() as f:
        actual_fixed = {line.strip() for line in f if line.strip()}
    assert actual_fixed == expected_fixed, (
        f'Archive contents do not match expected. Expected: {expected_fixed}; '
        f'Actual: {actual_fixed}'
    )

    for path in [LOG_DIR / 'old_app1.log', LOG_DIR / 'old_app2.log']:
        assert not path.exists(), f'Old log file {path} should have been deleted.'
    for path in [LOG_DIR / 'new_app1.log', LOG_DIR / 'new_app2.log']:
        assert path.is_file(), f'New log file {path} should NOT have been deleted.'

    assert FILTER_BIN.is_file(), f'C++ binary {FILTER_BIN} does not exist.'
    assert os.access(FILTER_BIN, os.X_OK), f'C++ binary {FILTER_BIN} is not executable.'
    assert SCRIPT.is_file(), f'Shell script {SCRIPT} does not exist.'
    assert os.access(SCRIPT, os.X_OK), f'Shell script {SCRIPT} is not executable.'

    # Verify that the requested C++ source exists, compiles, and produced a real binary.
    assert FILTER_SRC.is_file(), f'C++ source {FILTER_SRC} does not exist.'
    assert FILTER_SRC.stat().st_size > 0, 'C++ source is empty.'
    with FILTER_BIN.open('rb') as f:
        assert f.read(4) == b'\x7fELF', 'log_filter is not a compiled ELF executable.'

    token = secrets.token_hex(10)
    levels = ['INFO', 'ERROR', 'WARNING', 'CRITICAL', 'DEBUG', 'ERROR']
    filter_input = []
    filter_expected = []
    for i, level in enumerate(levels):
        a, b, c, d = 20 + i, 40 + i, 60 + i, 80 + i
        line = (f'[2026-08-{10+i:02d} 12:34:{10+i:02d}] [{level}] '
                f'[{a}.{b}.{c}.{d}] verifier-{token}-{i}')
        filter_input.append(line)
        if level in ('ERROR', 'CRITICAL'):
            filter_expected.append(
                line.replace(f'[{a}.{b}.{c}.{d}]', f'[{a}.{b}.{c}.XXX]')
            )

    assert run_filter(FILTER_BIN, filter_input) == filter_expected

    rebuilt = Path('/tmp') / f'rebuilt_filter_{token}'
    compile_result = subprocess.run(
        ['g++', '-std=c++17', str(FILTER_SRC), '-o', str(rebuilt)],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert compile_result.returncode == 0, f'C++ source does not compile:\n{compile_result.stderr}'

    # Exercise the rebuilt source implementation while the submitted binary path is absent.
    hidden_for_source = Path('/tmp') / f'original_filter_{token}'
    os.replace(FILTER_BIN, hidden_for_source)
    try:
        assert run_filter(rebuilt, filter_input) == filter_expected
    finally:
        os.replace(hidden_for_source, FILTER_BIN)
        rebuilt.unlink(missing_ok=True)

    script_text = SCRIPT.read_text(errors='replace')
    first_line = script_text.splitlines()[0] if script_text.splitlines() else ''
    assert first_line.startswith('#!') and 'bash' in first_line, 'process_logs.sh is not a bash script.'
    assert re.search(r'(?m)^[ \t]*(?!#).*\b(?:/[^ \t]*/)?find\b', script_text), \
        'process_logs.sh does not contain an active find command.'

    # Build unpredictable old/recent fixtures and run the submitted orchestration again.
    existing_logs = [p for p in LOG_DIR.rglob('*.log') if p.is_file()]
    existing_times = {p: (p.stat().st_atime_ns, p.stat().st_mtime_ns) for p in existing_logs}
    recent_time = time.time() - 24 * 60 * 60
    old_time = time.time() - 10 * 24 * 60 * 60
    for p in existing_logs:
        os.utime(p, (recent_time, recent_time))

    old_a = LOG_DIR / f'audit_old_{token}_a.log'
    old_b = LOG_DIR / f'audit_old_{token}_b.log'
    recent = LOG_DIR / f'audit_recent_{token}.log'
    old_nonlog = LOG_DIR / f'audit_old_{token}.txt'

    old_lines_a = [
        f'[2026-07-01 01:02:03] [INFO] [11.22.33.44] ignore-{token}',
        f'[2026-07-01 01:02:04] [ERROR] [101.102.103.104] err-{token}',
    ]
    old_lines_b = [
        f'[2026-07-02 02:03:04] [CRITICAL] [201.202.203.204] crit-{token}',
        f'[2026-07-02 02:03:05] [WARNING] [51.52.53.54] warn-{token}',
        f'[2026-07-02 02:03:06] [ERROR] [61.62.63.64] err2-{token}',
    ]
    recent_line = f'[2026-09-01 03:04:05] [ERROR] [71.72.73.74] recent-{token}'
    old_a.write_text('\n'.join(old_lines_a) + '\n')
    old_b.write_text('\n'.join(old_lines_b) + '\n')
    recent.write_text(recent_line + '\n')
    old_nonlog.write_text('must remain\n')
    for p in (old_a, old_b, old_nonlog):
        os.utime(p, (old_time, old_time))
    os.utime(recent, (recent_time, recent_time))

    expected_archive = [
        f'[2026-07-01 01:02:04] [ERROR] [101.102.103.XXX] err-{token}',
        f'[2026-07-02 02:03:04] [CRITICAL] [201.202.203.XXX] crit-{token}',
        f'[2026-07-02 02:03:06] [ERROR] [61.62.63.XXX] err2-{token}',
    ]
    expected_filter_input = old_lines_a + old_lines_b

    marker = Path('/tmp') / f'filter_stdin_{token}'
    saved_binary = Path('/tmp') / f'saved_filter_{token}'
    ARCHIVE.unlink(missing_ok=True)
    os.replace(FILTER_BIN, saved_binary)
    wrapper = f'''#!/usr/bin/python3
import subprocess, sys
data = sys.stdin.buffer.read()
with open({str(marker)!r}, 'ab') as out:
    out.write(data)
p = subprocess.run([{str(saved_binary)!r}], input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
sys.stdout.buffer.write(p.stdout)
sys.stderr.buffer.write(p.stderr)
sys.exit(p.returncode)
'''
    FILTER_BIN.write_text(wrapper)
    FILTER_BIN.chmod(0o755)

    try:
        result = subprocess.run(
            ['/bin/bash', '-x', str(SCRIPT)],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
        )
        assert result.returncode == 0, f'process_logs.sh failed:\n{result.stderr}'
        assert re.search(r'(?m)^\++\s+(?:command\s+)?(?:/\S*/)?find(?:\s|$)', result.stderr), \
            'The orchestration script did not execute find.'
        assert marker.is_file(), 'process_logs.sh did not pipe log data through /home/user/log_filter.'
        assert collections.Counter(marker.read_text().splitlines()) == collections.Counter(expected_filter_input), \
            'The filter did not receive exactly the contents of the old .log files.'

        assert ARCHIVE.is_file(), 'The dynamic archive was not created.'
        assert collections.Counter(ARCHIVE.read_text().splitlines()) == collections.Counter(expected_archive), \
            'Dynamic archive contents are incorrect.'
        assert not old_a.exists() and not old_b.exists(), 'Processed old .log files were not deleted.'
        assert recent.is_file(), 'A recent .log file was incorrectly deleted.'
        assert recent.read_text().splitlines() == [recent_line], 'A recent .log file was modified.'
        assert old_nonlog.is_file(), 'An old non-.log file was incorrectly deleted.'
        for p in existing_logs:
            assert p.is_file(), f'An existing recent log was incorrectly deleted: {p}'
    finally:
        FILTER_BIN.unlink(missing_ok=True)
        if saved_binary.exists():
            os.replace(saved_binary, FILTER_BIN)
        marker.unlink(missing_ok=True)
        for p in (old_a, old_b, recent, old_nonlog):
            p.unlink(missing_ok=True)
        for p, (atime_ns, mtime_ns) in existing_times.items():
            if p.exists():
                os.utime(p, ns=(atime_ns, mtime_ns))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
