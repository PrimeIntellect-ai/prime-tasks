#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import stat
import subprocess
import tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

import pytest

HOME = Path('/home/user')
APP_DATA = HOME / 'app_data'
SOURCE = HOME / 'monitor.rs'
SCRIPT = HOME / 'ci_step.sh'
BINARY = HOME / 'monitor'
LOG = HOME / 'build.log'
LINE_RE = re.compile(r'^Status: (PASS|FAIL) - (\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})$')


def test_monitor_rs_exists():
    """Verify that the Rust source file exists."""
    assert SOURCE.is_file(), f'File {SOURCE} is missing.'


def test_ci_step_sh_exists_and_executable():
    """Verify that the CI script exists and is executable."""
    assert SCRIPT.is_file(), f'File {SCRIPT} is missing.'
    st = SCRIPT.stat()
    assert bool(st.st_mode & stat.S_IXUSR), f'File {SCRIPT} is not executable.'


def test_build_log_exists_and_format():
    """Verify that build.log exists and contains the correct FAIL message with the date format."""
    assert LOG.is_file(), f'File {LOG} is missing. Did you run the script?'
    lines = LOG.read_text().strip().split('\n')
    assert len(lines) > 0, f'File {LOG} is empty.'
    last_line = lines[-1].strip()
    pattern = r'^Status: FAIL - \d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$'
    assert re.match(pattern, last_line) is not None, (
        f'The last line in {LOG} does not match the expected format or status. '
        f"Expected pattern '{pattern}', but got: '{last_line}'"
    )


def test_compiled_binary_exists():
    """Verify that the Rust program was compiled."""
    assert BINARY.is_file(), f'Compiled binary {BINARY} is missing. The CI script should compile monitor.rs.'
    st = BINARY.stat()
    assert bool(st.st_mode & stat.S_IXUSR), f'Compiled binary {BINARY} is not executable.'


def clear_app_data():
    APP_DATA.mkdir(parents=True, exist_ok=True)
    for child in APP_DATA.iterdir():
        if child.is_dir() and not child.is_symlink():
            shutil.rmtree(child)
        else:
            child.unlink()


def populate(total):
    clear_app_data()
    remaining = total
    index = 0
    while remaining:
        size = min(remaining, secrets.randbelow(min(remaining, 1300)) + 1)
        (APP_DATA / f'{secrets.token_hex(6)}-{index}.bin').write_bytes(os.urandom(size))
        remaining -= size
        index += 1

    # Files below subdirectories must not contribute to the flat-directory total.
    nested = APP_DATA / f'nested-{secrets.token_hex(6)}'
    nested.mkdir()
    (nested / 'ignored.bin').write_bytes(os.urandom(9000))


def run_monitor(path, expected):
    result = subprocess.run(
        [str(path)], cwd=str(HOME), stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=15
    )
    assert result.returncode == expected, (
        f'Monitor returned {result.returncode}, expected {expected}. stderr={result.stderr!r}'
    )
    assert result.stdout == b'', f'Monitor produced standard output: {result.stdout!r}'


def test_rust_program_and_ci_script_behavior():
    # Compile the submitted Rust source independently so a pre-existing fake
    # executable cannot satisfy the health-check tests.
    with tempfile.TemporaryDirectory(prefix='monitor-verify-') as td:
        independently_compiled = Path(td) / secrets.token_hex(8)
        compiled = subprocess.run(
            ['rustc', str(SOURCE), '-o', str(independently_compiled)],
            cwd=str(HOME), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            timeout=60
        )
        assert compiled.returncode == 0, f'monitor.rs did not compile: {compiled.stderr.decode(errors="replace")}'
        assert independently_compiled.is_file()

        cases = [0, secrets.randbelow(4999) + 1, 5000, 5001, 5002 + secrets.randbelow(4000)]
        for total in cases:
            populate(total)
            run_monitor(independently_compiled, 1 if total > 5000 else 0)

    tokyo = ZoneInfo('Asia/Tokyo')
    for total, expected_status, expected_code in [(5000, 'PASS', 0), (5001, 'FAIL', 1)]:
        populate(total)
        if BINARY.exists() or BINARY.is_symlink():
            BINARY.unlink()

        sentinel = f'sentinel-{secrets.token_hex(12)}'
        LOG.write_text(sentinel + '\n')
        before = datetime.now(timezone.utc)
        result = subprocess.run(
            [str(SCRIPT)], cwd=str(HOME),
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            env={**os.environ, 'TZ': 'UTC'}, timeout=60
        )
        after = datetime.now(timezone.utc)

        assert BINARY.is_file(), 'ci_step.sh did not create the compiled monitor binary.'
        assert os.access(BINARY, os.X_OK), 'The monitor produced by ci_step.sh is not executable.'
        assert BINARY.read_bytes()[:4] == b'\x7fELF', 'ci_step.sh did not produce a compiled native binary.'
        run_monitor(BINARY, expected_code)

        lines = LOG.read_text().splitlines()
        assert len(lines) == 2 and lines[0] == sentinel, (
            'ci_step.sh must append exactly one line to build.log without replacing existing content.'
        )
        match = LINE_RE.fullmatch(lines[1])
        assert match is not None, f'Invalid log line: {lines[1]!r}'
        assert match.group(1) == expected_status, (
            f'Expected {expected_status} for {total} bytes, got {match.group(1)}.'
        )

        logged_local = datetime.strptime(match.group(2), '%Y-%m-%d %H:%M:%S').replace(tzinfo=tokyo)
        logged_utc = logged_local.astimezone(timezone.utc)
        assert before - timedelta(seconds=3) <= logged_utc <= after + timedelta(seconds=3), (
            f'Log timestamp {match.group(2)!r} is not the current Asia/Tokyo time.'
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
