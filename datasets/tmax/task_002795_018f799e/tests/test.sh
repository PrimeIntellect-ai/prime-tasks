#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import struct
import subprocess
import wave
import pytest

PIPELINE_DIR = '/home/user/pipeline'
RUN_SH = os.path.join(PIPELINE_DIR, 'run.sh')
AGGREGATE_CPP = os.path.join(PIPELINE_DIR, 'aggregate.cpp')
OUTPUT_PATH = os.path.join(PIPELINE_DIR, 'final_output.txt')

@pytest.fixture(scope='session', autouse=True)
def run_pipeline_fresh():
    assert os.path.isfile(RUN_SH), f'Missing pipeline runner: {RUN_SH}'
    assert os.path.isfile(AGGREGATE_CPP), f'Missing aggregation source: {AGGREGATE_CPP}'
    assert not os.path.islink(AGGREGATE_CPP), 'aggregate.cpp must be a real source file, not a symlink'

    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)

    result = subprocess.run(
        [RUN_SH],
        cwd=PIPELINE_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert result.returncode == 0, (
        f'run.sh failed with exit code {result.returncode}.\n'
        f'stdout:\n{result.stdout.decode(errors="replace")}\n'
        f'stderr:\n{result.stderr.decode(errors="replace")}'
    )
    assert os.path.exists(OUTPUT_PATH), (
        f'Output file missing after executing {RUN_SH}: {OUTPUT_PATH}'
    )


def compute_reference(wav_path):
    with wave.open(wav_path, 'rb') as wf:
        n_frames = wf.getnframes()
        data = wf.readframes(n_frames)
        samples = struct.unpack(f'<{n_frames}h', data)

    cumulative = 0.0
    ref = []
    for s in samples:
        val = s / 32768.0
        cumulative += (val * val)
        ref.append(cumulative)
    return ref


def test_final_output_mse():
    wav_path = '/app/diagnostic_recording.wav'
    output_path = '/home/user/pipeline/final_output.txt'

    assert os.path.exists(output_path), f'Output file missing: {output_path}. Did the pipeline run successfully?'

    ref_data = compute_reference(wav_path)

    agent_data = []
    with open(output_path, 'r') as f:
        for line in f:
            if line.strip():
                try:
                    agent_data.append(float(line))
                except ValueError:
                    pytest.fail(f"Could not parse line as float: '{line.strip()}'. Ensure debug logs are not in stdout.")

    assert len(agent_data) == len(ref_data), f'Length mismatch in {output_path}: expected {len(ref_data)} lines, but got {len(agent_data)} lines.'

    mse = sum((a - r)**2 for a, r in zip(agent_data, ref_data)) / len(ref_data)

    threshold = 1e-10
    assert mse <= threshold, f'MSE is too high: {mse} > {threshold}. Double-precision floats and proper formatting are required.'


def test_aggregate_cpp_precision_and_stream_separation(tmp_path):
    binary = tmp_path / 'aggregate_under_test'
    compile_result = subprocess.run(
        ['g++', '-std=c++17', '-O2', AGGREGATE_CPP, '-o', str(binary)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert compile_result.returncode == 0, (
        'aggregate.cpp did not compile successfully:\n' +
        compile_result.stderr.decode(errors='replace')
    )

    rng = random.Random(int.from_bytes(os.urandom(16), 'big'))
    rendered = []
    expected = []
    cumulative = 0.0
    for i in range(20050):
        if i % 7 == 0:
            value = 0.99999999 if i % 2 else -0.99999999
        else:
            value = rng.uniform(-1.0, 1.0)
        text = f'{value:.8f}'
        parsed = float(text)
        rendered.append(text)
        cumulative += parsed * parsed
        expected.append(cumulative)

    result = subprocess.run(
        [str(binary)],
        input=('\n'.join(rendered) + '\n').encode(),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert result.returncode == 0, (
        f'Compiled aggregate exited with {result.returncode}:\n' +
        result.stderr.decode(errors='replace')
    )

    stdout_lines = result.stdout.decode(errors='replace').splitlines()
    assert len(stdout_lines) == len(expected), (
        f'aggregate stdout must contain exactly one numeric metric per sample; '
        f'expected {len(expected)} lines, got {len(stdout_lines)}'
    )

    actual = []
    for index, line in enumerate(stdout_lines, 1):
        try:
            value = float(line.strip())
        except ValueError:
            pytest.fail(f'Non-numeric text found on aggregate stdout at line {index}: {line!r}')
        assert math.isfinite(value), f'Non-finite metric on aggregate stdout at line {index}'
        actual.append(value)

    max_error = max(abs(a - e) for a, e in zip(actual, expected))
    assert max_error <= 1e-9, (
        f'aggregate cumulative energy lacks required double precision or output precision; '
        f'maximum absolute error was {max_error}'
    )

    stderr_text = result.stderr.decode(errors='replace')
    assert 'TRACE:' in stderr_text, 'Intermediate TRACE logging is missing from aggregate stderr'
    assert '10000' in stderr_text and '20000' in stderr_text, (
        'Expected intermediate state traces at 10000 and 20000 samples on stderr'
    )
    assert all('TRACE:' not in line for line in stdout_lines), (
        'TRACE logging polluted aggregate stdout instead of being sent to stderr'
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
