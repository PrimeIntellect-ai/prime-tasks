#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import shutil
import struct
import subprocess
import wave
from pathlib import Path

import numpy as np
import pandas as pd
import pytest

CSV_PATH = Path('/home/user/artifacts/experiment_results.csv')
WAV_PATH = Path('/app/machine_sound.wav')
FRAME_SIZE = 1600
BENCH_RE = re.compile(r'^Average inference time per frame: ([0-9]+(?:\.[0-9]{3})) microseconds$', re.MULTILINE)


def expected_probabilities(samples):
    n_frames = len(samples) // FRAME_SIZE
    result = []
    p_A, p_I = 0.1, 0.9
    for i in range(n_frames):
        frame = np.asarray(samples[i * FRAME_SIZE:(i + 1) * FRAME_SIZE], dtype=np.float64)
        rms = np.sqrt(np.mean(np.square(frame)))

        p_A_pred = p_A * 0.95 + p_I * 0.05
        p_I_pred = p_A * 0.05 + p_I * 0.95
        lik_A = (1.0 / (1000 * np.sqrt(2 * np.pi))) * np.exp(-0.5 * ((rms - 5000) / 1000) ** 2)
        lik_I = (1.0 / (200 * np.sqrt(2 * np.pi))) * np.exp(-0.5 * ((rms - 500) / 200) ** 2)
        unnorm_A = p_A_pred * lik_A
        unnorm_I = p_I_pred * lik_I
        p_A = unnorm_A / (unnorm_A + unnorm_I)
        p_I = unnorm_I / (unnorm_A + unnorm_I)
        result.append(p_A)
    return np.asarray(result)


def read_wav_samples(path):
    with wave.open(str(path), 'rb') as f:
        assert f.getnchannels() == 1, 'Input WAV must be mono'
        assert f.getsampwidth() == 2, 'Input WAV must contain 16-bit PCM samples'
        assert f.getframerate() == 16000, 'Input WAV must be 16kHz'
        count = f.getnframes()
        data = f.readframes(count)
    return struct.unpack(f'<{count}h', data)


def write_test_wav(path, amplitudes):
    samples = []
    for amplitude in amplitudes:
        frame = [amplitude if i % 2 == 0 else -amplitude for i in range(FRAME_SIZE)]
        samples.extend(frame)
    with wave.open(str(path), 'wb') as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(16000)
        f.writeframes(struct.pack(f'<{len(samples)}h', *samples))
    return samples


def source_candidates():
    found = []
    for root in ('/home/user', '/app', '/workspace'):
        base = Path(root)
        if base.exists():
            for path in base.rglob('*.c'):
                try:
                    if path.is_file() and path.stat().st_size <= 2_000_000:
                        text = path.read_text(errors='ignore')
                        if re.search(r'\bmain\s*\(', text):
                            found.append((path, text))
                except OSError:
                    pass
    return found


def check_c_source(main_path):
    directory = main_path.parent
    source_files = [main_path]
    for p in sorted(directory.glob('*.c')):
        if p != main_path:
            try:
                text = p.read_text(errors='ignore')
            except OSError:
                continue
            if not re.search(r'\bmain\s*\(', text):
                source_files.append(p)

    combined = '\n'.join(p.read_text(errors='ignore') for p in source_files)
    lower = combined.lower()

    assert not re.search(r'\b(system|popen|execl|execv|execvp|fork)\s*\(', combined), \
        'The C pipeline may not delegate its work to another program.'
    assert 'python' not in lower, 'The primary inference implementation must be C, not Python invoked from C.'
    assert re.search(r'\b(sqrt|sqrtf|sqrtl)\s*\(', combined), 'C source does not compute RMS with sqrt.'
    assert re.search(r'\b(exp|expf|expl)\s*\(', combined), 'C source does not implement Gaussian likelihoods.'
    assert ('0.95' in combined or '.95' in combined) and ('0.05' in combined or '.05' in combined), \
        'C source does not contain the required transition probabilities.'
    assert '5000' in combined and '1000' in combined and '500' in combined and '200' in combined, \
        'C source does not contain the required observation-model parameters.'

    timing_calls = list(re.finditer(r'\b(?:clock_gettime|timespec_get|gettimeofday|clock)\s*\(', combined))
    assert timing_calls, 'C source does not use a standard timing API.'
    assert ('clock_monotonic' in lower or 'timespec_get' in lower or 'gettimeofday' in lower or re.search(r'\bclock\s*\(', lower)), \
        'C source does not identify a usable clock for the benchmark.'

    # For direct start/end clock calls, ensure at least one measured region contains
    # inference work but no obvious RMS calculation or file/console I/O.
    if len(timing_calls) >= 2:
        clean_region = False
        for first, second in zip(timing_calls, timing_calls[1:]):
            span = combined[first.end():second.start()].lower()
            no_io_or_rms = not re.search(r'\b(?:sqrt|sqrtf|sqrtl|fread|fwrite|fopen|fclose|printf|fprintf|scanf|fscanf)\s*\(', span)
            inference_present = (
                re.search(r'\b(?:bayes|infer|filter|predict|posterior|update)[a-z0-9_]*\s*\(', span)
                or (re.search(r'\b(?:exp|expf|expl)\s*\(', span) and ('0.95' in span or '.95' in span))
            )
            if no_io_or_rms and inference_present:
                clean_region = True
                break
        assert clean_region, 'The timed block must contain Bayesian inference while excluding RMS and I/O.'

    return source_files


def run_binary(executable, cwd):
    CSV_PATH.unlink(missing_ok=True)
    proc = subprocess.run([str(executable)], cwd=str(cwd), stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, text=True, timeout=20)
    assert proc.returncode == 0, f'C pipeline failed with exit code {proc.returncode}: {proc.stderr}'
    match = BENCH_RE.search(proc.stdout)
    assert match, ('Standard output must contain the exact benchmark line '
                   "'Average inference time per frame: [X.XXX] microseconds'.")
    assert math.isfinite(float(match.group(1))) and float(match.group(1)) >= 0
    assert CSV_PATH.exists() and CSV_PATH.is_file(), f'The artifact file {CSV_PATH} does not exist.'
    return proc


def validate_csv(expected, threshold):
    try:
        df = pd.read_csv(CSV_PATH)
    except Exception as e:
        pytest.fail(f'Failed to read CSV {CSV_PATH}: {e}')

    assert list(df.columns) == ['frame_index', 'prob_active'], \
        "CSV header must be exactly 'frame_index,prob_active'"
    assert len(df) == len(expected), f'Expected {len(expected)} rows in CSV, got {len(df)}'
    indices = pd.to_numeric(df['frame_index'], errors='coerce').to_numpy()
    assert np.all(np.isfinite(indices)), 'frame_index must contain numeric values'
    assert np.array_equal(indices, np.arange(len(expected))), 'frame_index must be 0-indexed and sequential'
    probs = pd.to_numeric(df['prob_active'], errors='coerce').to_numpy()
    assert np.all(np.isfinite(probs)), 'prob_active must contain finite numeric values'
    assert np.all((probs >= 0.0) & (probs <= 1.0)), 'prob_active values must be probabilities'
    mae = np.mean(np.abs(probs - expected))
    assert mae < threshold, f'MAE of prob_active is {mae}, which is not below the threshold of {threshold}'
    return df


def compile_pipeline():
    candidates = source_candidates()
    assert candidates, 'No C source file containing main() was found under /home/user, /app, or /workspace.'
    failures = []
    build_dir = Path('/tmp/verified_c_build')
    shutil.rmtree(build_dir, ignore_errors=True)
    build_dir.mkdir(parents=True)

    for index, (main_path, _) in enumerate(candidates):
        try:
            source_files = check_c_source(main_path)
        except AssertionError as e:
            failures.append(f'{main_path}: {e}')
            continue
        executable = build_dir / f'pipeline_{index}'
        command = ['gcc', '-std=c11', '-O3', '-D_POSIX_C_SOURCE=200809L']
        command.extend(str(p) for p in source_files)
        command.extend(['-lm', '-o', str(executable)])
        proc = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        if proc.returncode != 0:
            failures.append(f'{main_path}: optimized compilation failed: {proc.stderr}')
            continue
        try:
            run_binary(executable, main_path.parent)
        except Exception as e:
            failures.append(f'{main_path}: compiled program did not run correctly: {e}')
            continue
        return executable, main_path.parent

    pytest.fail('No valid C pipeline could be compiled with -O3 and executed.\n' + '\n'.join(failures))


def test_c_pipeline_and_experiment_results():
    assert WAV_PATH.exists(), f'The audio file {WAV_PATH} is missing.'
    original_wav = WAV_PATH.read_bytes()
    executable = None
    cwd = None
    try:
        executable, cwd = compile_pipeline()

        # Preserve the original verifier's recomputation and MAE assertions.
        original_samples = read_wav_samples(WAV_PATH)
        original_expected = expected_probabilities(original_samples)
        run_binary(executable, cwd)
        df = validate_csv(original_expected, 0.01)
        agent_probs = df['prob_active'].values
        mae = np.mean(np.abs(agent_probs - original_expected))
        threshold = 0.01
        assert mae < threshold, f'MAE of prob_active is {mae}, which is not below the threshold of {threshold}'

        # Exercise the compiled C implementation on unseen RMS sequences so a
        # fixed CSV or near-binary state labels cannot satisfy the verifier.
        hidden_cases = [
            [500, 1000, 1300, 1500, 1800, 1000, 500],
            [2200, 1400, 900, 5000, 3200, 1600, 700, 1200, 2000, 500],
        ]
        for amplitudes in hidden_cases:
            samples = write_test_wav(WAV_PATH, amplitudes)
            expected = expected_probabilities(samples)
            run_binary(executable, cwd)
            validate_csv(expected, 0.0002)
    finally:
        WAV_PATH.write_bytes(original_wav)
        if executable is not None and executable.exists():
            # Leave the requested artifact corresponding to the real input.
            run_binary(executable, cwd)

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
