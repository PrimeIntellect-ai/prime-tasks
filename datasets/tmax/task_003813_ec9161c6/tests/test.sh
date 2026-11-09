#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import statistics
import subprocess
from pathlib import Path

HOME = Path('/home/user')
DATA = HOME / 'recovered_data.csv'
SCRIPT = HOME / 'process_data.py'
RESULT = HOME / 'result.txt'


def expected_recovered_lines():
    return [
        'CORRUPTED_DATA_ENTRY_MISSING_SENSOR' if i == 100
        else f'{1000000000.0 + i * 0.001:.3f}'
        for i in range(200)
    ]


def run_script():
    assert SCRIPT.is_file(), f'The required script {SCRIPT} does not exist.'
    RESULT.unlink(missing_ok=True)
    proc = subprocess.run(
        ['python3', str(SCRIPT)],
        cwd=str(HOME),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert proc.returncode == 0, (
        f'{SCRIPT} exited with status {proc.returncode}. stderr: {proc.stderr!r}'
    )
    assert proc.stdout == '', f'The script should run silently, but printed: {proc.stdout!r}'
    assert proc.stderr == '', f'The script should silently ignore malformed lines, but wrote: {proc.stderr!r}'
    assert RESULT.is_file(), f'The script did not create {RESULT}.'
    return RESULT.read_text().strip()


def test_recovered_data():
    """Verify that the deleted file was recovered exactly."""
    path = '/home/user/recovered_data.csv'
    assert os.path.isfile(path), f'The file {path} does not exist. Did you recover it?'

    raw = Path(path).read_text()
    lines = raw.splitlines()

    assert len(lines) == 200, f'Expected 200 lines in {path}, got {len(lines)}.'
    assert lines[100] == 'CORRUPTED_DATA_ENTRY_MISSING_SENSOR', 'The corrupted line is missing or at the wrong index.'
    assert lines[0] == '1000000000.000', f'First line is incorrect, got {lines[0]}.'
    assert lines[-1] == '1000000000.199', f'Last line is incorrect, got {lines[-1]}.'

    expected_lines = expected_recovered_lines()
    assert lines == expected_lines, 'The recovered file does not exactly match the deleted data.'
    assert raw == '\n'.join(expected_lines) + '\n', 'The recovered file contents are not exact.'


def test_process_data_on_unpredictable_inputs():
    """Execute the repaired script against malformed and cancellation-prone data."""
    original = DATA.read_bytes()
    rng = secrets.SystemRandom()

    try:
        base = 10**12 + rng.randrange(1_000_000, 9_000_000)
        offsets = [rng.randrange(-64, 65) for _ in range(95)] + [-64, 64]
        large_values = [f'{base + offset / 8:.3f}' for offset in offsets]
        large_floats = [float(value) for value in large_values]
        large_lines = large_values + ['', 'not-a-number-value', '12.5broken', '--7']
        rng.shuffle(large_lines)

        normal_values = [f'{rng.randrange(-500000, 500001) / 10000:.9f}' for _ in range(43)]
        normal_floats = [float(value) for value in normal_values]
        normal_lines = normal_values + ['CORRUPTED', ' ', '3.4.5']
        rng.shuffle(normal_lines)

        cases = [
            (large_lines, large_floats),
            (normal_lines, normal_floats),
            (['bad', '', '   ', f'{rng.randrange(-10000, 10001) / 10:.1f}', '1e2oops'], None),
        ]

        for lines, valid_values in cases:
            if valid_values is None:
                valid_values = [float(lines[3])]
            DATA.write_text('\n'.join(lines) + '\n')
            expected = f'{statistics.pstdev(valid_values):.4f}'
            actual = run_script()
            assert actual == expected, (
                f'For verifier-generated input, expected {RESULT} to contain '
                f'{expected!r}, but got {actual!r}.'
            )
    finally:
        DATA.write_bytes(original)


def test_result_txt():
    """Run the fixed script on the recovered file and verify the final result."""
    content = run_script()

    data = []
    for i in range(200):
        if i != 100:
            data.append(1000000000.0 + i * 0.001)

    expected_pstdev = statistics.pstdev(data)
    expected_str = f'{expected_pstdev:.4f}'

    assert content == expected_str, f"Expected {RESULT} to contain '{expected_str}', but got '{content}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
