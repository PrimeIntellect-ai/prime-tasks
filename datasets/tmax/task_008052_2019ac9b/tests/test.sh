#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import struct
import subprocess
from pathlib import Path

import pytest

RUN_SH = Path('/home/user/run.sh')
ETL_DIR = Path('/home/user/etl')
CARGO_TOML = ETL_DIR / 'Cargo.toml'
DATA_PATH = Path('/home/user/sensor_data.csv')
OUTPUT_PATH = Path('/home/user/output.txt')
PIPELINE_STATE = {}


def to_f32(val):
    """Simulate 32-bit float precision."""
    return struct.unpack('f', struct.pack('f', val))[0]


def compute_expected_final_state(data_path):
    """Compute the expected mu and var sequentially from the CSV file."""
    mu = to_f32(0.0)
    var = to_f32(1.0)
    var_v = to_f32(2.0)

    w_x = to_f32(0.5)
    w_y = to_f32(0.5)
    w_z = to_f32(0.707)

    with open(data_path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue

            parts = line.split(',')
            x = to_f32(float(parts[0]))
            y = to_f32(float(parts[1]))
            z = to_f32(float(parts[2]))

            v = to_f32(to_f32(w_x * x) + to_f32(w_y * y) + to_f32(w_z * z))

            new_mu = to_f32(to_f32(mu * var_v + v * var) / to_f32(var + var_v))
            new_var = to_f32(to_f32(var * var_v) / to_f32(var + var_v))

            mu = new_mu
            var = new_var

    return mu, var


def expected_string(data_path=DATA_PATH):
    mu, var = compute_expected_final_state(data_path)
    return f"Final State: mu={mu:.4f}, var={var:.4f}"


def run_command(command, cwd=None):
    return subprocess.run(
        command,
        cwd=cwd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=180,
        env={k: v for k, v in os.environ.items() if k != 'CARGO_TARGET_DIR'},
    )


def remove_output():
    try:
        OUTPUT_PATH.unlink()
    except FileNotFoundError:
        pass


def read_output():
    assert OUTPUT_PATH.exists(), '/home/user/output.txt was not generated.'
    assert OUTPUT_PATH.is_file(), '/home/user/output.txt is not a file.'
    return OUTPUT_PATH.read_text().strip()


def discover_release_binaries():
    result = run_command(
        ['cargo', 'metadata', '--format-version', '1', '--no-deps',
         '--manifest-path', str(CARGO_TOML)],
        cwd=ETL_DIR,
    )
    assert result.returncode == 0, (
        f"Cargo metadata failed.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    metadata = json.loads(result.stdout)
    target_dir = Path(metadata['target_directory']) / 'release'
    binaries = []
    for package in metadata['packages']:
        for target in package.get('targets', []):
            if 'bin' in target.get('kind', []):
                candidate = target_dir / target['name']
                if candidate not in binaries:
                    binaries.append(candidate)
    return binaries


def test_00_run_pipeline_from_clean_build():
    """Actually execute run.sh and require it to create a native release binary."""
    assert RUN_SH.exists(), f"{RUN_SH} does not exist."
    assert RUN_SH.is_file(), f"{RUN_SH} is not a file."
    assert os.access(RUN_SH, os.X_OK), f"{RUN_SH} is not executable."
    assert CARGO_TOML.exists(), f"Rust project not found. Expected {CARGO_TOML}."

    shutil.rmtree(ETL_DIR / 'target', ignore_errors=True)
    remove_output()
    result = run_command([str(RUN_SH)], cwd=Path('/home/user'))
    assert result.returncode == 0, (
        f"run.sh failed.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert read_output() == expected_string()

    binaries = discover_release_binaries()
    assert binaries, 'Cargo.toml defines no Rust binary target.'
    existing = []
    for binary in binaries:
        if binary.is_file() and os.access(binary, os.X_OK):
            with binary.open('rb') as f:
                if f.read(4) == b'\x7fELF':
                    existing.append(binary)
    assert existing, (
        'run.sh did not produce an executable native binary in Cargo\'s release directory.'
    )
    PIPELINE_STATE['binaries'] = existing


def test_run_sh_exists_and_executable():
    """Check that run.sh exists and is executable."""
    script_path = '/home/user/run.sh'
    assert os.path.exists(script_path), f"{script_path} does not exist."
    assert os.path.isfile(script_path), f"{script_path} is not a file."
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable."


def test_rust_project_exists():
    """Check that the Rust project was created in /home/user/etl."""
    cargo_toml_path = '/home/user/etl/Cargo.toml'
    assert os.path.exists(cargo_toml_path), f"Rust project not found. Expected {cargo_toml_path}."


def test_output_file_exists():
    """Check that output.txt was generated."""
    output_path = '/home/user/output.txt'
    assert os.path.exists(output_path), f"{output_path} does not exist."
    assert os.path.isfile(output_path), f"{output_path} is not a file."


def test_output_content():
    """Check that output.txt contains the correctly computed final state."""
    output_path = '/home/user/output.txt'
    data_path = '/home/user/sensor_data.csv'

    assert os.path.exists(output_path), 'Cannot check content, output.txt missing.'
    assert os.path.exists(data_path), 'Cannot compute expected state, sensor_data.csv missing.'

    expected_mu, expected_var = compute_expected_final_state(data_path)

    with open(output_path, 'r') as f:
        content = f.read().strip()

    expected = f"Final State: mu={expected_mu:.4f}, var={expected_var:.4f}"
    assert content == expected, (
        f"Output content mismatch.\nExpected: '{expected}'\nGot: '{content}'"
    )


def make_random_csv():
    rng = secrets.SystemRandom()
    rows = []
    for _ in range(rng.randint(2, 8)):
        values = [rng.randint(-200000, 200000) / 10000.0 for _ in range(3)]
        rows.append(','.join(f'{value:.6f}' for value in values))
    return ('\n'.join(rows) + '\n').encode()


def test_pipeline_and_rust_binary_on_unseen_inputs():
    """Exercise both run.sh and its compiled Rust artifact on runtime-generated data."""
    assert PIPELINE_STATE.get('binaries'), 'No release Rust binaries were recorded.'
    original_data = DATA_PATH.read_bytes()
    original_output = OUTPUT_PATH.read_bytes() if OUTPUT_PATH.exists() else None
    viable_binaries = list(PIPELINE_STATE['binaries'])

    try:
        for _ in range(3):
            DATA_PATH.write_bytes(make_random_csv())
            expected = expected_string()

            remove_output()
            result = run_command([str(RUN_SH)], cwd=Path('/home/user'))
            assert result.returncode == 0, (
                f"run.sh failed on an unseen input.\n"
                f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
            )
            assert read_output() == expected, 'run.sh produced an incorrect dynamic result.'

            passing = []
            for binary in viable_binaries:
                remove_output()
                result = run_command([str(binary)], cwd=ETL_DIR)
                if result.returncode == 0 and OUTPUT_PATH.is_file():
                    if OUTPUT_PATH.read_text().strip() == expected:
                        passing.append(binary)
            viable_binaries = passing
            assert viable_binaries, (
                'No compiled release Rust binary correctly processed the unseen input.'
            )
    finally:
        DATA_PATH.write_bytes(original_data)
        if original_output is None:
            remove_output()
        else:
            OUTPUT_PATH.write_bytes(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
