#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY' > /tmp/test_final_state.py
import math
import os
import secrets
import stat
import subprocess
from pathlib import Path

SOURCE = Path('/home/user/aggregate.c')
SCRIPT = Path('/home/user/run_pipeline.sh')
BINARY = Path('/home/user/aggregate')
RAW = Path('/home/user/raw_telemetry.csv')
SUMMARY = Path('/home/user/summary.csv')


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=30, **kwargs)


def expected_output(data):
    buckets = {}
    for line in data.splitlines():
        if line.count(',') != 4:
            continue
        timestamp, x, y, z, status = line.split(',')
        try:
            timestamp = int(timestamp)
            magnitude = math.sqrt(float(x) ** 2 + float(y) ** 2 + float(z) ** 2)
        except ValueError:
            continue
        bucket = timestamp // 3600
        buckets.setdefault(bucket, []).append(magnitude)
    return '\n'.join(
        f'{bucket},{sum(values) / len(values):.2f}'
        for bucket, values in sorted(buckets.items())
    )


def make_input():
    base = 400000 + secrets.randbelow(200000)
    offsets = sorted({secrets.randbelow(20) for _ in range(12)})
    while len(offsets) < 6:
        offsets = sorted(set(offsets) | {secrets.randbelow(20)})
    vectors = [(3, 4, 0), (5, 12, 0), (6, 8, 0), (1, 2, 2), (2, 3, 6)]
    lines = []
    for i in range(24):
        bucket = base + secrets.choice(offsets)
        x, y, z = secrets.choice(vectors)
        scale = 1 + secrets.randbelow(7)
        signs = [secrets.choice((-1, 1)) for _ in range(3)]
        timestamp = bucket * 3600 + secrets.randbelow(3600)
        status = 'S' + secrets.token_hex(5)
        lines.append(
            f'{timestamp},{x * scale * signs[0]}.0,{y * scale * signs[1]}.0,'
            f'{z * scale * signs[2]}.0,{status}'
        )
    lines.extend([
        'fragment-' + secrets.token_hex(6),
        f'{base * 3600},1,2,3,TOO,MANY',
        '1,2,3',
        ',,,',
    ])
    secrets.SystemRandom().shuffle(lines)
    return '\n'.join(lines) + '\n'


def assert_elf(path):
    assert path.is_file(), f'{path} was not created as a regular file'
    assert os.access(path, os.X_OK), f'{path} is not executable'
    with path.open('rb') as f:
        assert f.read(4) == b'\x7fELF', f'{path} is not an ELF executable'


def test_aggregate_c_exists():
    assert SOURCE.is_file(), '/home/user/aggregate.c does not exist'


def test_run_pipeline_script_exists_and_executable():
    assert SCRIPT.is_file(), '/home/user/run_pipeline.sh does not exist'
    mode = SCRIPT.stat().st_mode
    assert mode & stat.S_IXUSR, '/home/user/run_pipeline.sh is not executable by its owner'


def test_pipeline_execution_and_output():
    original_data = RAW.read_bytes()

    for path in (SUMMARY, BINARY):
        if path.exists():
            path.unlink()
    result = run([str(SCRIPT)])
    assert result.returncode == 0, f'Pipeline failed: {result.stderr}'
    assert_elf(BINARY)
    assert SUMMARY.is_file(), '/home/user/summary.csv was not created'

    fixture_lines = SUMMARY.read_text().strip().splitlines()
    allowed_fixture_results = [
        ['472222,9.00', '472223,6.50', '472224,13.00'],
        ['472222,9.33', '472223,6.50', '472224,13.00'],
    ]
    assert fixture_lines in allowed_fixture_results, f'Unexpected fixture output: {fixture_lines}'

    generated = make_input()
    expected = expected_output(generated).splitlines()
    try:
        RAW.write_text(generated)
        for path in (SUMMARY, BINARY):
            if path.exists():
                path.unlink()
        result = run([str(SCRIPT)])
        assert result.returncode == 0, f'Pipeline failed on generated input: {result.stderr}'
        assert RAW.read_text() == generated, 'The pipeline modified raw_telemetry.csv'
        assert_elf(BINARY)
        assert SUMMARY.is_file(), '/home/user/summary.csv was not recreated'
        actual = SUMMARY.read_text().splitlines()
        assert actual == expected, f'Expected {expected}, got {actual}'
    finally:
        RAW.write_bytes(original_data)


def test_source_compiles_and_handles_unseen_inputs():
    output_binary = Path('/tmp/aggregate_from_submitted_source')
    if output_binary.exists():
        output_binary.unlink()
    result = run(['gcc', str(SOURCE), '-o', str(output_binary), '-lm'])
    assert result.returncode == 0, f'aggregate.c did not compile with -lm: {result.stderr}'
    assert_elf(output_binary)

    for _ in range(4):
        generated = make_input()
        expected = expected_output(generated).splitlines()
        result = run([str(output_binary)], input=generated)
        assert result.returncode == 0, f'Compiled aggregate failed: {result.stderr}'
        actual = result.stdout.splitlines()
        assert actual == expected, f'Expected {expected}, got {actual}'


def test_cron_job_installed():
    result = run(['crontab', '-l'])
    assert result.returncode == 0, 'Failed to read crontab'
    found = False
    for job in result.stdout.splitlines():
        if not job.strip() or job.lstrip().startswith('#'):
            continue
        parts = job.split()
        if len(parts) >= 6:
            minute, hour, dom, mon, dow = parts[:5]
            command = ' '.join(parts[5:])
            if (minute, hour, dom, mon, dow) == ('15', '*', '*', '*', '*') and '/home/user/run_pipeline.sh' in command:
                found = True
                break
    assert found, 'Cron job for /home/user/run_pipeline.sh at minute 15 was not installed'
PY

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo 1 > /logs/verifier/reward.txt
else
    echo 0 > /logs/verifier/reward.txt
fi
