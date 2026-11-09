#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import subprocess
from pathlib import Path

TOOL_DIR = Path('/home/user/metrics_tool')
TOOL = TOOL_DIR / 'metrics_tool'
SCRIPT = Path('/home/user/test_script.py')
LOG = Path('/home/user/test_results.log')


def run_tool(input_data):
    process = subprocess.Popen(
        [str(TOOL)],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    stdout, stderr = process.communicate(input=input_data, timeout=10)
    assert process.returncode == 0, (
        f'metrics_tool exited with non-zero status: {process.returncode}. '
        f'Stderr: {stderr}'
    )
    return stdout


def oracle_output(records):
    counts = {}
    window = []
    output = []
    for timestamp, value in records:
        count = counts.get(timestamp, 0)
        if count >= 2:
            output.append(f'{timestamp},RATE_LIMIT_EXCEEDED')
            continue
        counts[timestamp] = count + 1
        window.append(value)
        window = window[-3:]
        output.append(f'{timestamp},{sum(window) / len(window):.2f}')
    return '\n'.join(output) + '\n'


def test_00_makefile_builds_real_executable():
    for name in ('metrics_tool', 'main.o', 'calculator.o', 'rate_limiter.o'):
        path = TOOL_DIR / name
        if path.exists() or path.is_symlink():
            path.unlink()

    result = subprocess.run(
        ['make'], cwd=TOOL_DIR, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30,
    )
    assert result.returncode == 0, (
        f'make failed.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )
    assert TOOL.is_file(), f'{TOOL} executable not found. Did make run successfully?'
    assert os.access(TOOL, os.X_OK), f'{TOOL} is not executable.'
    with TOOL.open('rb') as f:
        assert f.read(4) == b'\x7fELF', 'metrics_tool is not a compiled ELF executable'


def test_01_test_results_log():
    assert LOG.is_file(), f'{LOG} not found. Did you run the test script and redirect its output?'
    content = LOG.read_text().strip()
    assert content == 'ALL_TESTS_PASS', (
        f"Expected 'ALL_TESTS_PASS' in {LOG}, got '{content}'"
    )


def test_02_metrics_tool_disclosed_output():
    input_data = '1,10.0\n1,20.0\n1,30.0\n2,40.0\n'
    expected_output = '1,10.00\n1,15.00\n1,RATE_LIMIT_EXCEEDED\n2,23.33\n'
    stdout = run_tool(input_data)
    assert stdout == expected_output, (
        f'metrics_tool output mismatch.\nExpected:\n{expected_output}\nGot:\n{stdout}'
    )


def test_03_calculator_rolling_window_on_undisclosed_inputs(tmp_path):
    harness = tmp_path / 'calculator_harness.cpp'
    executable = tmp_path / 'calculator_harness'
    harness.write_text(r'''#include <cstdlib>
#include <iomanip>
#include <iostream>
#include "calculator.h"
int main(int argc, char **argv) {
    std::cout << std::setprecision(17);
    for (int i = 1; i < argc; ++i) {
        std::cout << compute_sma(std::stod(argv[i])) << "\n";
    }
    return 0;
}
''')
    build = subprocess.run(
        ['g++', '-std=c++11', '-I', str(TOOL_DIR), str(harness),
         str(TOOL_DIR / 'calculator.cpp'), '-o', str(executable)],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30,
    )
    assert build.returncode == 0, f'calculator.cpp failed to compile:\n{build.stderr}'

    rng = random.SystemRandom()
    sequences = [
        [7.0, -2.0, 19.0, 4.0, 31.0, -11.0],
        [float(rng.randint(-1000, 1000)) for _ in range(12)],
        [float(rng.randint(-5000, 5000)) for _ in range(9)],
    ]
    for values in sequences:
        result = subprocess.run(
            [str(executable), *[repr(v) for v in values]],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10,
        )
        assert result.returncode == 0, result.stderr
        actual = [float(line) for line in result.stdout.splitlines()]
        expected = [sum(values[max(0, i - 2):i + 1]) / min(3, i + 1)
                    for i in range(len(values))]
        assert len(actual) == len(expected)
        for got, want in zip(actual, expected):
            assert math.isclose(got, want, rel_tol=1e-12, abs_tol=1e-12), (
                f'compute_sma returned {got}, expected {want} for sequence {values}'
            )


def test_04_metrics_tool_on_undisclosed_rate_and_sma_cases():
    rng = random.SystemRandom()
    cases = [
        [(8, -9), (9, 12), (8, 21), (8, 99), (10, 6), (9, 3), (9, 42)],
        [(4, 5), (4, 8), (5, 14), (4, 100), (6, -7), (5, 20), (6, 2)],
    ]
    cases.append([
        (rng.randint(20, 25), rng.randint(-1000, 1000))
        for _ in range(35)
    ])

    for records in cases:
        input_data = ''.join(f'{timestamp},{value}\n' for timestamp, value in records)
        expected = oracle_output(records)
        actual = run_tool(input_data)
        assert actual == expected, (
            f'Unexpected output for records {records}.\nExpected:\n{expected}\nGot:\n{actual}'
        )


def test_05_integration_script_runs_tool_and_detects_failure(tmp_path):
    assert SCRIPT.is_file(), f'{SCRIPT} not found'
    real_tool = TOOL_DIR / '.verifier_real_metrics_tool'
    capture = tmp_path / 'captured_stdin'
    expected_input = b'1,10.0\n1,20.0\n1,30.0\n2,40.0\n'

    TOOL.rename(real_tool)
    try:
        TOOL.write_text(
            '#!/bin/sh\n'
            f'cat > {capture}\n'
            f'{real_tool} < {capture}\n'
        )
        TOOL.chmod(0o755)
        good = subprocess.run(
            ['python3', str(SCRIPT)], text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15,
        )
        assert good.returncode == 0, good.stderr
        assert good.stdout.strip() == 'ALL_TESTS_PASS', (
            f'test_script.py did not pass with the correct tool: {good.stdout!r}'
        )
        assert capture.read_bytes() == expected_input, (
            'test_script.py did not feed the required exact input to metrics_tool'
        )

        TOOL.write_text(
            '#!/bin/sh\n'
            f'cat > {capture}\n'
            "printf '1,999.00\\n1,999.00\\n1,999.00\\n2,999.00\\n'\n"
        )
        TOOL.chmod(0o755)
        bad = subprocess.run(
            ['python3', str(SCRIPT)], text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15,
        )
        assert bad.returncode == 0, bad.stderr
        assert capture.read_bytes() == expected_input, (
            'test_script.py did not run metrics_tool when checking bad output'
        )
        assert bad.stdout.strip() == 'FAIL', (
            f'test_script.py accepted incorrect tool output: {bad.stdout!r}'
        )
    finally:
        if TOOL.exists() or TOOL.is_symlink():
            TOOL.unlink()
        if real_tool.exists():
            real_tool.rename(TOOL)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
