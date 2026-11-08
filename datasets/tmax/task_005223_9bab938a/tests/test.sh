#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import tempfile
from pathlib import Path

import numpy as np
import pandas as pd
import pytest

RESULT = Path('/home/user/result.csv')


def generate_reference():
    cmd = [
        'ffmpeg', '-i', '/app/sensor_video.mp4',
        '-vf', 'format=gray,scale=1:1',
        '-f', 'image2pipe',
        '-vcodec', 'rawvideo',
        '-pix_fmt', 'gray',
        '-'
    ]
    try:
        process = subprocess.run(cmd, capture_output=True, check=True)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to extract frames from video using ffmpeg: {e.stderr.decode(errors='replace')}")

    brightness = [float(b) for b in process.stdout]
    assert len(brightness) > 0, 'Error: No frames extracted from video.'

    resampled = []
    for i in range(0, len(brightness) - len(brightness) % 3, 3):
        resampled.append(np.mean(brightness[i:i + 3]))

    sma = []
    for i in range(len(resampled) - 3):
        sma.append(np.mean(resampled[i:i + 4]))

    sma = np.array(sma)
    normalized = (sma - sma.min()) / (sma.max() - sma.min())
    return normalized


def validate_generated_result(reference):
    if not RESULT.is_file():
        return False, 'did not create /home/user/result.csv'
    try:
        agent_df = pd.read_csv(RESULT)
    except Exception as e:
        return False, f'created an unreadable CSV: {e}'

    if list(agent_df.columns) != ['idx', 'value']:
        return False, f'created columns {list(agent_df.columns)}'
    if len(agent_df) != len(reference):
        return False, f'created {len(agent_df)} rows instead of {len(reference)}'
    if not pd.api.types.is_integer_dtype(agent_df['idx'].dtype):
        return False, 'idx is not an integer column'
    if not np.array_equal(agent_df['idx'].to_numpy(), np.arange(len(reference))):
        return False, 'idx is not the required 0-based sequential index'
    try:
        values = pd.to_numeric(agent_df['value'], errors='raise').to_numpy(dtype=float)
    except Exception as e:
        return False, f'value is not numeric: {e}'
    if not np.all(np.isfinite(values)):
        return False, 'value contains non-finite entries'
    mse = np.mean((reference - values) ** 2)
    if mse > 0.001:
        return False, f'MSE {mse:.6f} exceeds 0.001'
    return True, ''


def discover_rust_artifacts():
    roots = ['/home', '/app', '/workspace', '/root', '/tmp']
    manifests = []
    sources = []
    pruned = {'.git', '.cargo', 'target', '__pycache__', 'tests', 'logs'}

    for root in roots:
        if not os.path.isdir(root):
            continue
        for current, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if d not in pruned]
            if 'Cargo.toml' in files:
                manifests.append(Path(current) / 'Cargo.toml')
            for name in files:
                if name.endswith('.rs'):
                    sources.append(Path(current) / name)

    manifests = sorted(set(p.resolve() for p in manifests))
    cargo_dirs = [p.parent for p in manifests]

    standalone = []
    for source in sorted(set(p.resolve() for p in sources)):
        if not any(cargo_dir == source.parent or cargo_dir in source.parents for cargo_dir in cargo_dirs):
            standalone.append(source)
    return manifests, standalone


def run_candidate(command, cwd, reference):
    RESULT.unlink(missing_ok=True)
    try:
        completed = subprocess.run(
            command, cwd=str(cwd), capture_output=True, text=True, timeout=120
        )
    except Exception as e:
        return False, f"{' '.join(command)}: {e}"

    if completed.returncode != 0:
        detail = (completed.stderr or completed.stdout)[-500:]
        return False, f"{' '.join(command)} exited {completed.returncode}: {detail}"

    valid, reason = validate_generated_result(reference)
    if valid:
        return True, ''
    return False, f"{' '.join(command)} {reason}"


def test_result_csv_exists():
    assert os.path.exists('/home/user/result.csv'), 'The output file /home/user/result.csv does not exist.'
    assert os.path.isfile('/home/user/result.csv'), '/home/user/result.csv is not a file.'


def test_rust_program_regenerates_result():
    """Compile and execute submitted Rust processing code without trusting the prewritten CSV."""
    reference = generate_reference()
    manifests, standalone_sources = discover_rust_artifacts()
    assert manifests or standalone_sources, 'No submitted Rust source or Cargo project was found.'

    failures = []
    for manifest in manifests:
        ok, reason = run_candidate(
            ['cargo', 'run', '--quiet', '--manifest-path', str(manifest)],
            manifest.parent,
            reference,
        )
        if ok:
            return
        failures.append(reason)

        try:
            metadata = subprocess.run(
                ['cargo', 'metadata', '--no-deps', '--format-version', '1',
                 '--manifest-path', str(manifest)],
                cwd=str(manifest.parent), capture_output=True, text=True,
                timeout=60, check=True,
            )
            import json
            data = json.loads(metadata.stdout)
            bins = []
            for package in data.get('packages', []):
                for target in package.get('targets', []):
                    if 'bin' in target.get('kind', []):
                        bins.append(target['name'])
            for binary in bins:
                ok, reason = run_candidate(
                    ['cargo', 'run', '--quiet', '--manifest-path', str(manifest),
                     '--bin', binary],
                    manifest.parent,
                    reference,
                )
                if ok:
                    return
                failures.append(reason)
        except Exception as e:
            failures.append(f'Could not inspect Cargo targets in {manifest}: {e}')

    with tempfile.TemporaryDirectory() as tempdir:
        for number, source in enumerate(standalone_sources):
            executable = Path(tempdir) / f'candidate_{number}'
            try:
                compiled = subprocess.run(
                    ['rustc', str(source), '-O', '-o', str(executable)],
                    cwd=str(source.parent), capture_output=True, text=True,
                    timeout=120,
                )
            except Exception as e:
                failures.append(f'Could not compile {source}: {e}')
                continue
            if compiled.returncode != 0:
                failures.append(f'Could not compile {source}: {compiled.stderr[-500:]}')
                continue
            ok, reason = run_candidate([str(executable)], source.parent, reference)
            if ok:
                return
            failures.append(reason)

    pytest.fail('No submitted Rust program regenerated a valid result.csv. ' + ' | '.join(failures[-8:]))


def test_result_csv_format_and_mse():
    """Verify the format of the result CSV and compute the MSE against the reference truth."""
    normalized = generate_reference()
    reference_df = pd.DataFrame({
        'idx': range(len(normalized)),
        'value': normalized
    })

    try:
        agent_df = pd.read_csv('/home/user/result.csv')
    except Exception as e:
        pytest.fail(f'Could not read /home/user/result.csv as a CSV file: {e}')

    assert list(agent_df.columns) == ['idx', 'value'], f"Expected columns ['idx', 'value'], but got {list(agent_df.columns)}"

    min_len = min(len(reference_df), len(agent_df))
    assert min_len > 0, 'Agent CSV contains no data rows.'
    assert len(agent_df) == len(reference_df), f'Expected {len(reference_df)} rows, but got {len(agent_df)} rows.'

    assert pd.api.types.is_integer_dtype(agent_df['idx'].dtype), 'idx column must contain integers.'
    expected_idx = np.arange(len(reference_df), dtype=np.int64)
    assert np.array_equal(agent_df['idx'].to_numpy(), expected_idx), 'idx must be the 0-based sequential sequence 0,1,2,...'

    ref_vals = reference_df['value'].values[:min_len]
    try:
        agent_vals = pd.to_numeric(agent_df['value'], errors='raise').to_numpy(dtype=float)[:min_len]
    except Exception as e:
        pytest.fail(f'value column must contain numeric floats: {e}')
    assert np.all(np.isfinite(agent_vals)), 'value column contains non-finite values.'

    mse = np.mean((ref_vals - agent_vals) ** 2)
    assert mse <= 0.001, f'Failure: MSE {mse:.6f} exceeds threshold of 0.001.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
