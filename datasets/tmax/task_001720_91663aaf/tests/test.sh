#!/bin/bash
set -e
mkdir -p /logs/verifier

# Stop any process already listening on port 8123 so verification uses a
# verifier-controlled server backed by the current test fixture.
python3 - <<'PY'
import os
import signal

inodes = set()
for table in ("/proc/net/tcp", "/proc/net/tcp6"):
    try:
        with open(table) as f:
            next(f, None)
            for line in f:
                fields = line.split()
                if len(fields) >= 10 and fields[1].rsplit(':', 1)[-1].upper() == '1FBB' and fields[3] == '0A':
                    inodes.add(fields[9])
    except OSError:
        pass

for pid in os.listdir('/proc'):
    if not pid.isdigit() or int(pid) == os.getpid():
        continue
    fd_dir = f'/proc/{pid}/fd'
    try:
        for fd in os.listdir(fd_dir):
            try:
                target = os.readlink(f'{fd_dir}/{fd}')
            except OSError:
                continue
            if target.startswith('socket:[') and target[8:-1] in inodes:
                try:
                    os.kill(int(pid), signal.SIGKILL)
                except (ProcessLookupError, PermissionError):
                    pass
                break
    except OSError:
        pass
PY

python3 -m http.server 8123 --directory /home/user >/tmp/verifier_log_server.log 2>&1 &
SERVER_PID=$!
trap 'kill "$SERVER_PID" 2>/dev/null || true' EXIT

for _ in $(seq 1 50); do
    if curl -fsS http://localhost:8123/raw_logs.csv >/dev/null 2>&1; then
        break
    fi
    sleep 0.1
done

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import subprocess
from pathlib import Path

HOME = Path('/home/user')


def test_pipeline_script_exists():
    path = HOME / 'pipeline.sh'
    assert path.is_file(), f'Pipeline script is missing at {path}.'


def test_cpp_processor_exists():
    path = HOME / 'process_logs.cpp'
    assert path.is_file(), f'C++ source file is missing at {path}.'


def expected_values(rows):
    valid = sorted((float(t), float(v)) for t, v in rows if float(v) >= 0)
    result = []
    for target in range(6):
        exact = [v for t, v in valid if t == target]
        if exact:
            result.append(exact[-1])
            continue
        left = [(t, v) for t, v in valid if t < target]
        right = [(t, v) for t, v in valid if t > target]
        assert left and right, 'Verifier fixture must bracket every target timestamp.'
        t0, v0 = left[-1]
        t1, v1 = right[0]
        result.append(v0 + (v1 - v0) * (target - t0) / (t1 - t0))

    mean = sum(result) / len(result)
    stddev = math.sqrt(sum((v - mean) ** 2 for v in result) / len(result))
    return [(v - mean) / stddev for v in result]


def write_fixture(rows):
    text = 'timestamp,value\n' + ''.join(f'{t},{v}\n' for t, v in rows)
    (HOME / 'raw_logs.csv').write_text(text)


def run_pipeline():
    for path in (HOME / 'processed_logs.csv', HOME / 'processor'):
        try:
            path.unlink()
        except FileNotFoundError:
            pass
    proc = subprocess.run(
        ['bash', str(HOME / 'pipeline.sh')],
        cwd=str(HOME),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert proc.returncode == 0, f'pipeline.sh failed:\nSTDOUT:\n{proc.stdout}\nSTDERR:\n{proc.stderr}'
    assert (HOME / 'processor').is_file(), 'pipeline.sh did not compile /home/user/processor.'
    assert os.access(HOME / 'processor', os.X_OK), '/home/user/processor is not executable.'
    assert (HOME / 'processed_logs.csv').is_file(), 'pipeline.sh did not generate processed_logs.csv.'


def check_output(expected):
    path = HOME / 'processed_logs.csv'
    lines = [line.strip() for line in path.read_text().splitlines() if line.strip()]
    assert len(lines) == 6, f'Expected exactly 6 lines in {path}, but found {len(lines)}.'

    seen = set()
    for line in lines:
        parts = line.split(',')
        assert len(parts) == 2, f"Line '{line}' is not in 'timestamp,normalized_value' format."
        try:
            timestamp = int(parts[0])
            value = float(parts[1])
        except ValueError:
            raise AssertionError(f"Could not parse timestamp as int and value as float from line '{line}'.")

        assert timestamp in range(6), f"Unexpected timestamp '{timestamp}' found."
        assert timestamp not in seen, f"Duplicate timestamp '{timestamp}' found."
        seen.add(timestamp)
        assert re.fullmatch(r'-?\d+\.\d{4}', parts[1]), f"Value '{parts[1]}' does not have exactly 4 decimal places."
        assert math.isfinite(value), f'Value at t={timestamp} is not finite.'
        assert abs(value - expected[timestamp]) < 0.0002, (
            f'Value at t={timestamp} is {value}, expected approximately {expected[timestamp]:.4f}.'
        )

    assert seen == set(range(6)), f'Expected unique timestamps 0 through 5, found {sorted(seen)}.'


def test_pipeline_on_derived_input_and_restore_final_output():
    rng = random.SystemRandom()
    base = rng.uniform(6.0, 18.0)
    rows = [
        ('0.0', f'{base:.7f}'),
        ('0.8', f'{base + rng.uniform(2.0, 7.0):.7f}'),
        ('1.5', f'{-rng.uniform(1.0, 20.0):.7f}'),
        ('2.2', f'{base + rng.uniform(8.0, 16.0):.7f}'),
        ('3.7', f'{base + rng.uniform(17.0, 27.0):.7f}'),
        ('5.4', f'{base + rng.uniform(29.0, 42.0):.7f}'),
    ]
    write_fixture(rows)
    run_pipeline()
    check_output(expected_values(rows))

    canonical = [
        ('0.0', '10.0'),
        ('1.2', '16.0'),
        ('1.5', '-5.0'),
        ('2.5', '22.5'),
        ('4.0', '30.0'),
        ('5.1', '35.5'),
    ]
    write_fixture(canonical)
    run_pipeline()


def test_processed_logs_exists():
    path = HOME / 'processed_logs.csv'
    assert path.is_file(), f'Final output file is missing at {path}.'


def test_processed_logs_content():
    expected = {
        0: -1.4638501,
        1: -0.8783100,
        2: -0.2927700,
        3: 0.2927700,
        4: 0.8783100,
        5: 1.4638501,
    }
    check_output(expected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
