#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
from pathlib import Path

import numpy as np
import scipy.io.wavfile as wavfile
import pytest

PIPELINE = Path('/home/user/run_pipeline.sh')


def compute_reference_correlation(audio_path):
    rate, data = wavfile.read(audio_path)
    if data.ndim > 1:
        data = data[:, 0]

    samples_per_chunk = 16000
    samples_per_window = 1600

    num_chunks = len(data) // samples_per_chunk
    features = []

    for i in range(num_chunks):
        chunk = data[i*samples_per_chunk : (i+1)*samples_per_chunk]
        chunk_features = []
        for j in range(10):
            window = chunk[j*samples_per_window : (j+1)*samples_per_window]
            mav = np.mean(np.abs(window.astype(float)))
            chunk_features.append(mav)
        features.append(chunk_features)

    features = np.array(features)
    corr_matrix = np.corrcoef(features)
    return corr_matrix


def expected_similar(corr_matrix):
    corr_with_00 = corr_matrix[0, 1:]
    corrs = [(-corr_with_00[i], i + 1) for i in range(len(corr_with_00))]
    corrs.sort()
    return [x[1] for x in corrs[:3]]


def load_and_check_csv(path, expected):
    assert os.path.exists(path), f"Agent file not found: {path}"
    try:
        actual = np.loadtxt(path, delimiter=',')
    except Exception as e:
        pytest.fail(f"Failed to load {path} as CSV: {e}")

    assert actual.shape == expected.shape, \
        f"Shape mismatch: agent {actual.shape} != ref {expected.shape}"
    mae = np.mean(np.abs(expected - actual))
    assert mae <= 0.001, f"MAE {mae} exceeds threshold 0.001"

    lines = Path(path).read_text().splitlines()
    assert len(lines) == expected.shape[0], "Incorrect number of CSV rows"
    number = re.compile(r'-?(?:0|[1-9][0-9]*)\.[0-9]{6}')
    for line in lines:
        fields = line.split(',')
        assert len(fields) == expected.shape[1], "Incorrect number of CSV columns"
        assert all(number.fullmatch(field) for field in fields), \
            "correlation.csv values must use exactly 6 decimal places"


def load_and_check_similar(path, expected_indices):
    assert os.path.exists(path), f"Agent file not found: {path}"
    content = Path(path).read_text().strip()
    assert content, "similar.txt is empty"
    try:
        actual = [int(x.strip()) for x in content.split(',')]
    except ValueError:
        pytest.fail(f"Could not parse similar.txt contents: {content}")
    assert actual == expected_indices, \
        f"Expected indices {expected_indices}, got {actual}"


def check_chunks(input_audio, chunks_dir, count):
    assert chunks_dir.is_dir(), f"Missing chunks directory: {chunks_dir}"
    expected_names = [f'chunk_{i:02d}.wav' for i in range(count)]
    actual_names = sorted(p.name for p in chunks_dir.glob('*.wav'))
    assert actual_names == expected_names, \
        f"Expected chunk files {expected_names}, got {actual_names}"

    input_rate, input_data = wavfile.read(input_audio)
    for i, name in enumerate(expected_names):
        rate, data = wavfile.read(chunks_dir / name)
        assert rate == 16000, f"{name} has sample rate {rate}, expected 16000"
        assert len(data) == 16000, f"{name} does not contain exactly 16000 samples"
        expected_data = input_data[i*16000:(i+1)*16000]
        assert data.shape == expected_data.shape, f"Unexpected shape for {name}"
        assert np.array_equal(data, expected_data), \
            f"{name} does not contain the corresponding one-second input segment"


def test_correlation_matrix_mae():
    agent_file = '/home/user/artifacts/correlation.csv'
    assert os.path.exists(agent_file), f"Agent file not found: {agent_file}"

    try:
        agent_matrix = np.loadtxt(agent_file, delimiter=',')
    except Exception as e:
        pytest.fail(f"Failed to load {agent_file} as CSV: {e}")

    ref_matrix = compute_reference_correlation('/app/experiment_audio.wav')

    assert agent_matrix.shape == ref_matrix.shape, f"Shape mismatch: agent {agent_matrix.shape} != ref {ref_matrix.shape}"

    mae = np.mean(np.abs(ref_matrix - agent_matrix))
    assert mae <= 0.001, f"MAE {mae} exceeds threshold 0.001"


def test_similar_txt():
    similar_file = '/home/user/artifacts/similar.txt'
    assert os.path.exists(similar_file), f"Agent file not found: {similar_file}"

    ref_matrix = compute_reference_correlation('/app/experiment_audio.wav')
    expected_indices = expected_similar(ref_matrix)

    with open(similar_file, 'r') as f:
        content = f.read().strip()

    assert content, "similar.txt is empty"
    try:
        agent_indices = [int(x.strip()) for x in content.split(',')]
    except ValueError:
        pytest.fail(f"Could not parse similar.txt contents: {content}")

    assert agent_indices == expected_indices, f"Expected indices {expected_indices}, got {agent_indices}"


def test_provided_run_created_required_chunks_and_formatting():
    ref = compute_reference_correlation('/app/experiment_audio.wav')
    load_and_check_csv('/home/user/artifacts/correlation.csv', ref)
    load_and_check_similar('/home/user/artifacts/similar.txt', expected_similar(ref))
    check_chunks(Path('/app/experiment_audio.wav'),
                 Path('/home/user/artifacts/chunks'), 20)


def test_pipeline_exists_argument_contract_and_reproducible_execution(tmp_path):
    assert PIPELINE.exists(), f"Required pipeline script not found: {PIPELINE}"
    assert PIPELINE.is_file(), f"Pipeline path is not a regular file: {PIPELINE}"

    input_audio = tmp_path / 'unseen_audio.wav'
    output_dir = tmp_path / 'artifacts'
    output_dir.mkdir()
    (output_dir / 'stale.txt').write_text('must be removed')
    (output_dir / 'chunks').mkdir()
    (output_dir / 'chunks' / 'obsolete.wav').write_bytes(b'obsolete')

    rng = np.random.default_rng(20260911)
    chunks = []
    for i in range(6):
        windows = []
        amplitudes = rng.integers(500, 14000, size=10)
        for j, amplitude in enumerate(amplitudes):
            signs = rng.choice(np.array([-1, 1], dtype=np.int16), size=1600)
            variation = ((np.arange(1600) * (i + j + 1)) % 97).astype(np.int32)
            window = signs.astype(np.int32) * (int(amplitude) + variation)
            windows.append(window.astype(np.int16))
        chunks.append(np.concatenate(windows))
    audio_data = np.concatenate(chunks)
    wavfile.write(input_audio, 16000, audio_data)

    result = subprocess.run(
        ['bash', str(PIPELINE), str(input_audio), str(output_dir)],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=120)
    assert result.returncode == 0, \
        f"Pipeline failed on a valid two-argument invocation:\n{result.stdout}\n{result.stderr}"

    assert not (output_dir / 'stale.txt').exists(), \
        "Pipeline did not clear the existing output directory"
    assert not (output_dir / 'chunks' / 'obsolete.wav').exists(), \
        "Pipeline retained stale chunk content"

    check_chunks(input_audio, output_dir / 'chunks', 6)
    ref = compute_reference_correlation(input_audio)
    load_and_check_csv(output_dir / 'correlation.csv', ref)
    load_and_check_similar(output_dir / 'similar.txt', expected_similar(ref))

    bad_calls = [
        ['bash', str(PIPELINE)],
        ['bash', str(PIPELINE), str(input_audio)],
        ['bash', str(PIPELINE), str(input_audio), str(tmp_path / 'three_args'), 'extra'],
    ]
    for command in bad_calls:
        bad = subprocess.run(command, cwd=tmp_path, stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE, text=True, timeout=30)
        assert bad.returncode != 0, \
            f"Pipeline must reject invocations with {len(command) - 2} arguments"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
