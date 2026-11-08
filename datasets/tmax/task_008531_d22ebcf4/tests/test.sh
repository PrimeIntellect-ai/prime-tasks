#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import concurrent.futures
import importlib.util
import inspect
import os
import random
import re
import subprocess
import tempfile
import time

APP_DIR = '/home/user/app'
SCRIPT_PATH = os.path.join(APP_DIR, 'aggregator.py')
LOG_PATH = os.path.join(APP_DIR, 'recovered_logs.txt')
DUMP_PATH = os.path.join(APP_DIR, 'crash_dump.bin')
METRIC_PATH = '/home/user/final_metric.txt'
OUTPUT_RE = re.compile(r'^Total Uptime: (-?\d+)$')
LOG_RE = re.compile(r'^UPTIME_PING=(\d+)$')


def run_aggregator(log_path):
    result = subprocess.run(
        ['python3', SCRIPT_PATH, log_path],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f'aggregator.py failed for {log_path}: {result.stderr}'
    )
    return result.stdout.strip()


def test_recovered_logs_exists():
    """Test that recovered_logs.txt exists and contains the dump's real records."""
    assert os.path.isfile(LOG_PATH), f'File {LOG_PATH} is missing. Did you extract the logs?'

    with open(LOG_PATH, 'r') as f:
        content = f.read()
    assert 'UPTIME_PING=' in content, (
        f"{LOG_PATH} does not contain the expected 'UPTIME_PING=' string."
    )

    with open(DUMP_PATH, 'rb') as f:
        dump = f.read()
    expected = [int(value) for value in re.findall(rb'UPTIME_PING=(\d+)(?=\n)', dump)]
    assert expected, 'The crash dump contains no recoverable uptime records.'

    recovered = []
    for line_number, line in enumerate(content.splitlines(), 1):
        if 'UPTIME_PING=' not in line:
            continue
        match = LOG_RE.fullmatch(line.strip())
        assert match, (
            f'Malformed recovered uptime record on line {line_number}: {line!r}'
        )
        recovered.append(int(match.group(1)))

    assert recovered == expected, (
        'recovered_logs.txt does not contain exactly the uptime records embedded '
        'in crash_dump.bin, in their original order.'
    )


def test_final_metric_correct():
    """Test that final_metric.txt contains the correct total uptime."""
    assert os.path.isfile(METRIC_PATH), (
        f'File {METRIC_PATH} is missing. Did you pipe the output?'
    )
    with open(METRIC_PATH, 'r') as f:
        content = f.read().strip()
    assert content == 'Total Uptime: 50000', (
        f"Expected 'Total Uptime: 50000' in {METRIC_PATH}, but got '{content}'."
    )


def test_aggregator_is_deterministic():
    """Preserve the original repeated recovered-log check."""
    assert os.path.isfile(SCRIPT_PATH), f'{SCRIPT_PATH} is missing.'
    assert os.path.isfile(LOG_PATH), f'{LOG_PATH} is missing.'
    for i in range(5):
        output = run_aggregator(LOG_PATH)
        assert output == 'Total Uptime: 50000', (
            'aggregator.py is not deterministic or incorrect. Expected '
            f"'Total Uptime: 50000', got '{output}' on iteration {i + 1}."
        )


def test_aggregator_on_derived_inputs():
    """Reject fixed answers by exercising independently generated log files."""
    rng = random.SystemRandom()
    for case in range(4):
        values = [rng.randint(1, 1000000) for _ in range(rng.randint(211, 389))]
        expected = sum(values)
        lines = []
        for index, value in enumerate(values):
            if index % 17 == 0:
                lines.append(f'IGNORED_EVENT={rng.randint(1, 999999)}\n')
            lines.append(f'UPTIME_PING={value}\n')

        with tempfile.NamedTemporaryFile('w', delete=False) as f:
            f.writelines(lines)
            path = f.name
        try:
            wanted = f'Total Uptime: {expected}'
            for iteration in range(3):
                output = run_aggregator(path)
                assert OUTPUT_RE.fullmatch(output), (
                    f'Unexpected standard output format: {output!r}'
                )
                assert output == wanted, (
                    f'Incorrect result for generated case {case + 1}, run '
                    f'{iteration + 1}: expected {wanted!r}, got {output!r}.'
                )
        finally:
            os.unlink(path)


def test_process_chunk_has_no_racy_shared_update():
    """Force a thread switch during integer addition to expose the original race."""
    spec = importlib.util.spec_from_file_location('submitted_aggregator', SCRIPT_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    process_chunk = getattr(module, 'process_chunk', None)
    if not callable(process_chunk):
        return  # A redesign without this shared-state worker is exercised via the CLI.

    try:
        inspect.signature(process_chunk).bind(['UPTIME_PING=1\n'])
    except TypeError:
        return  # A changed worker API is exercised through main instead.

    class SlowInt(int):
        def __add__(self, other):
            time.sleep(0.03)
            return SlowInt(int(self) + int(other))

        def __radd__(self, other):
            time.sleep(0.03)
            return SlowInt(int(other) + int(self))

    values = list(range(101, 113))
    expected = sum(values)
    module.total_uptime = SlowInt(0)
    chunks = [[f'UPTIME_PING={value}\n'] for value in values]
    with concurrent.futures.ThreadPoolExecutor(max_workers=len(chunks)) as executor:
        results = list(executor.map(process_chunk, chunks))

    shared_total = int(getattr(module, 'total_uptime', 0))
    returned = [value for value in results if isinstance(value, int)]
    returned_total = sum(returned) if len(returned) == len(values) else None
    assert shared_total == expected or returned_total == expected, (
        'process_chunk loses concurrent updates when addition yields the thread; '
        'protect shared updates with synchronization or aggregate worker returns.'
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
