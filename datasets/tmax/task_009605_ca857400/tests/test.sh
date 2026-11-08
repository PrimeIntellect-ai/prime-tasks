#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import math
import os
import re
import subprocess
from pathlib import Path

HOME = Path('/home/user')
OSC_EXE = '/tmp/oscillator_submission'
ANALYZE_EXE = '/tmp/analyze_submission'


def run(cmd, cwd=HOME):
    return subprocess.run(cmd, cwd=str(cwd), check=True, timeout=30,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)


def read_series():
    filepath = HOME / 'timeseries.csv'
    lines = filepath.read_text().splitlines()
    assert len(lines) == 1001, f'Expected exactly 1001 lines in timeseries.csv, but found {len(lines)}.'

    values = []
    for line_number, line in enumerate(lines, 1):
        parts = line.split(',')
        assert len(parts) == 2, f'Line {line_number} must have exactly two comma-separated values.'
        try:
            t, y = map(float, parts)
        except ValueError as exc:
            raise AssertionError(f'Line {line_number} does not contain two valid floats: {line!r}') from exc
        assert math.isfinite(t) and math.isfinite(y), f'Line {line_number} contains a non-finite value.'
        values.append((t, y))
    return lines, values


def expected_analysis(values):
    best_frequency = None
    best_magnitude = -1.0
    for k in range(491):
        frequency = 0.10 + 0.01 * k
        real = 0.0
        imag = 0.0
        for t, y in values:
            angle = 2.0 * math.pi * frequency * t
            real += y * math.cos(angle)
            imag -= y * math.sin(angle)
        magnitude = math.hypot(real, imag)
        if magnitude > best_magnitude:
            best_magnitude = magnitude
            best_frequency = frequency

    libc = ctypes.CDLL(None)
    libc.srand.argtypes = [ctypes.c_uint]
    libc.rand.argtypes = []
    libc.rand.restype = ctypes.c_int
    libc.srand(42)
    ys = [y for _, y in values]
    means = []
    for _ in range(1000):
        total = 0.0
        for _ in range(1001):
            total += ys[libc.rand() % 1001]
        means.append(total / 1001.0)
    means.sort()
    return best_frequency, means[24], means[974]


def validate_report(values):
    text = (HOME / 'report.txt').read_text()
    match = re.fullmatch(
        r'Dominant Frequency: (-?\d+\.\d{4}) Hz\n'
        r'Mean CI: \[(-?\d+\.\d{4}), (-?\d+\.\d{4})\]\n?',
        text,
    )
    assert match, f'report.txt does not have the exact required two-line format: {text!r}'
    actual = tuple(float(x) for x in match.groups())
    expected = expected_analysis(values)
    for name, got, want in zip(('dominant frequency', 'CI lower bound', 'CI upper bound'), actual, expected):
        assert abs(got - want) <= 0.000051, f'Incorrect {name}: got {got:.4f}, expected {want:.4f}'


def test_files_exist():
    """Verify that all required files exist."""
    required_files = [
        '/home/user/oscillator.c',
        '/home/user/timeseries.csv',
        '/home/user/analyze.c',
        '/home/user/report.txt'
    ]
    for filepath in required_files:
        assert os.path.isfile(filepath), f'Required file {filepath} is missing.'


def test_timeseries_format():
    """Verify that timeseries.csv has 1001 lines with t,y format."""
    lines, _ = read_series()
    first_line = lines[0].split(',')
    assert len(first_line) == 2, 'Each line in timeseries.csv must have exactly two comma-separated values.'
    t0 = float(first_line[0])
    y0 = float(first_line[1])
    assert abs(t0 - 0.0) < 1e-6, 'First t value should be 0.00'
    assert abs(y0 - 1.0) < 1e-6, 'First y value should be 1.00'


def test_report_content():
    """Verify the contents of report.txt match the expected format and values."""
    filepath = '/home/user/report.txt'
    content = Path(filepath).read_text().strip()
    expected_freq = r'Dominant Frequency:\s*1\.5800\s*Hz'
    expected_ci = r'Mean CI:\s*\[-0\.0101,\s*0\.0267\]'
    assert re.search(expected_freq, content), (
        f"Could not find the expected Dominant Frequency in {filepath}. "
        f"Expected 'Dominant Frequency: 1.5800 Hz'. File content:\n{content}"
    )
    assert re.search(expected_ci, content), (
        f"Could not find the expected Mean CI in {filepath}. "
        f"Expected 'Mean CI: [-0.0101, 0.0267]'. File content:\n{content}"
    )


def test_programs_execute_and_compute_results():
    run(['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', str(HOME / 'oscillator.c'), '-lm', '-o', OSC_EXE])
    run(['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', str(HOME / 'analyze.c'), '-lm', '-o', ANALYZE_EXE])

    # Execute the submitted simulator and validate every emitted sample against
    # an independently computed RK4 trajectory.
    (HOME / 'timeseries.csv').unlink(missing_ok=True)
    run([OSC_EXE])
    assert (HOME / 'timeseries.csv').is_file(), 'oscillator.c did not create timeseries.csv.'
    _, values = read_series()

    y = 1.0
    v = 0.0
    dt = 0.01
    for i, (actual_t, actual_y) in enumerate(values):
        expected_t = i * dt
        assert abs(actual_t - expected_t) <= 1e-7, f'Incorrect time at sample {i}: {actual_t}'
        assert abs(actual_y - y) <= 1.1e-6, f'Incorrect RK4 y value at sample {i}: got {actual_y}, expected {y}'

        k1y = v
        k1v = -100.0 * y - 2.0 * v
        k2y = v + 0.5 * dt * k1v
        k2v = -100.0 * (y + 0.5 * dt * k1y) - 2.0 * (v + 0.5 * dt * k1v)
        k3y = v + 0.5 * dt * k2v
        k3v = -100.0 * (y + 0.5 * dt * k2y) - 2.0 * (v + 0.5 * dt * k2v)
        k4y = v + dt * k3v
        k4v = -100.0 * (y + dt * k3y) - 2.0 * (v + dt * k3v)
        y += dt * (k1y + 2.0 * k2y + 2.0 * k3y + k4y) / 6.0
        v += dt * (k1v + 2.0 * k2v + 2.0 * k3v + k4v) / 6.0

    # Execute the submitted analyzer on the simulator's output and derive the
    # expected DFT and bootstrap answers independently.
    normal_csv = (HOME / 'timeseries.csv').read_bytes()
    (HOME / 'report.txt').unlink(missing_ok=True)
    run([ANALYZE_EXE])
    assert (HOME / 'report.txt').is_file(), 'analyze.c did not create report.txt.'
    validate_report(values)

    content = (HOME / 'report.txt').read_text().strip()
    assert re.search(r'Dominant Frequency:\s*1\.5800\s*Hz', content)
    assert re.search(r'Mean CI:\s*\[-0\.0101,\s*0\.0267\]', content)

    # A second, non-oscillator input prevents hardcoded report values from
    # passing while preserving the required 1001-sample input shape.
    with (HOME / 'timeseries.csv').open('w') as stream:
        for i in range(1001):
            t = i * 0.01
            sample = 0.35 + 0.8 * math.cos(2.0 * math.pi * 3.21 * t) + 0.17 * math.sin(2.0 * math.pi * 0.73 * t)
            stream.write(f'{t:.12f},{sample:.12f}\n')
    _, alternate_values = read_series()
    (HOME / 'report.txt').unlink(missing_ok=True)
    run([ANALYZE_EXE])
    validate_report(alternate_values)

    # Leave the required final artifacts corresponding to the requested run.
    (HOME / 'timeseries.csv').write_bytes(normal_csv)
    (HOME / 'report.txt').unlink(missing_ok=True)
    run([ANALYZE_EXE])
    _, restored_values = read_series()
    validate_report(restored_values)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
