#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess
from pathlib import Path

import pytest

SCRIPT = Path('/home/user/detect_cycle.sh')
CSV = Path('/home/user/transaction_locks.csv')
REPORT = Path('/home/user/deadlock_report.txt')
ORIGINAL_EXPECTED = 'TX_994 -> TX_772 -> TX_881 -> TX_994'


@pytest.fixture(scope='session', autouse=True)
def restore_files_after_tests():
    csv_data = CSV.read_bytes()
    report_existed = REPORT.exists()
    report_data = REPORT.read_bytes() if report_existed else b''
    yield
    CSV.write_bytes(csv_data)
    if report_existed:
        REPORT.write_bytes(report_data)
    else:
        REPORT.unlink(missing_ok=True)


def read_exact_report(expected):
    assert REPORT.is_file(), f'Report file not found: {REPORT}'
    raw = REPORT.read_text()
    assert raw in (expected, expected + '\n'), (
        f'Expected report content to be {expected!r}, but got {raw!r}'
    )


def run_detector(start):
    REPORT.unlink(missing_ok=True)
    result = subprocess.run(
        [str(SCRIPT), start],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=5,
    )
    assert result.returncode == 0, (
        f'detect_cycle.sh failed for {start}: stdout={result.stdout!r}, '
        f'stderr={result.stderr!r}'
    )


def make_random_graph():
    token = secrets.token_hex(6).upper()
    cycle = [f'TX_{token}_{i}' for i in range(6)]
    rows = []

    # Each cycle[i] waits for a resource granted to cycle[i+1].
    for i, waiter in enumerate(cycle):
        holder = cycle[(i + 1) % len(cycle)]
        resource = f'RES_{token}_C{i}'
        rows.append(f'{waiter},{resource},WAITING')
        rows.append(f'{holder},{resource},GRANTED')

    # Add a dead-end branch from the requested start, requiring traversal to
    # continue/backtrack rather than merely following the first dependency.
    dead1 = f'TX_{token}_DEAD1'
    dead2 = f'TX_{token}_DEAD2'
    r1 = f'RES_{token}_DEAD1'
    r2 = f'RES_{token}_DEAD2'
    rows.extend([
        f'{cycle[0]},{r1},WAITING',
        f'{dead1},{r1},GRANTED',
        f'{dead1},{r2},WAITING',
        f'{dead2},{r2},GRANTED',
        f'TX_{token}_NOISE,RES_{token}_NOISE,GRANTED',
    ])
    random.SystemRandom().shuffle(rows)
    CSV.write_text('\n'.join(rows) + '\n')
    return cycle


def test_script_exists_and_executable():
    """Test that the detect_cycle.sh script exists and is executable."""
    assert SCRIPT.is_file(), f'Script not found: {SCRIPT}'
    assert os.access(SCRIPT, os.X_OK), f'Script is not executable: {SCRIPT}'


def test_deadlock_report_exists():
    """Test that the initially requested deadlock report exists."""
    assert REPORT.is_file(), f'Report file not found: {REPORT}'


def test_deadlock_report_content():
    """Preserve the original exact check of the pre-generated report."""
    assert REPORT.is_file(), f'Cannot check content, file missing: {REPORT}'
    content = REPORT.read_text().strip()
    assert content == ORIGINAL_EXPECTED, (
        f'Expected report content to be {ORIGINAL_EXPECTED!r}, but got {content!r}'
    )


def test_executes_against_original_csv():
    """The executable itself must regenerate the required original report."""
    run_detector('TX_994')
    read_exact_report(ORIGINAL_EXPECTED)


def test_recursive_traversal_on_unseen_csv():
    """Exercise derived, unpredictable cycles instead of trusting a fixed report."""
    cycle = make_random_graph()
    for offset in (0, 2, 5):
        start = cycle[offset]
        ordered = cycle[offset:] + cycle[:offset] + [start]
        expected = ' -> '.join(ordered)
        run_detector(start)
        read_exact_report(expected)


def test_requires_exactly_one_argument():
    for args in ([], ['ONE', 'TWO']):
        REPORT.unlink(missing_ok=True)
        result = subprocess.run(
            [str(SCRIPT), *args],
            cwd='/home/user',
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=5,
        )
        assert result.returncode != 0, (
            f'Script must reject argument list {args!r}, but returned success'
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
