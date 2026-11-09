#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_task.py
import array
import json
import math
import os
import random
import shutil
import subprocess
from pathlib import Path

HOME = Path('/home/user')
DATA_FILE = HOME / 'data/features.bin'
METRICS_FILE = HOME / 'metrics.json'
ORIGINAL_EXPECTED = 2000.0


def validate_metrics(expected):
    assert METRICS_FILE.is_file(), f'File {METRICS_FILE} does not exist. The Rust program must create it.'
    try:
        with METRICS_FILE.open('r') as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        raise AssertionError(f'Failed to parse {METRICS_FILE} as JSON: {e}')

    assert 'l2_norm' in data, "The JSON file is missing the 'l2_norm' key."
    assert 'compute_time_us' in data, "The JSON file is missing the 'compute_time_us' key."

    l2_norm = data['l2_norm']
    time_us = data['compute_time_us']
    assert isinstance(l2_norm, (int, float)), f"'l2_norm' must be a number, got {type(l2_norm).__name__}"
    assert isinstance(time_us, int), f"'compute_time_us' must be an integer, got {type(time_us).__name__}"
    assert not isinstance(time_us, bool), "'compute_time_us' must be an integer, not a boolean"
    assert time_us >= 0, f"'compute_time_us' should be non-negative, got {time_us}"
    assert abs(l2_norm - expected) < 0.1, f'Incorrect L2 norm. Expected ~{expected}, got {l2_norm}'


def is_elf(path):
    try:
        with path.open('rb') as f:
            return f.read(4) == b'\x7fELF'
    except OSError:
        return False


def run_and_validate(executable, expected):
    try:
        METRICS_FILE.unlink()
    except FileNotFoundError:
        pass
    subprocess.run([str(executable)], cwd=str(executable.parent), check=True,
                   timeout=30, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    validate_metrics(expected)


def write_random_input():
    rng = random.Random(int.from_bytes(os.urandom(32), 'little'))
    vals = array.array('f')
    vals.fromlist([rng.choice((-2.0, -1.0, 0.0, 1.0, 2.0)) for _ in range(1_000_000)])
    sumsq = sum(int(v) * int(v) for v in vals)
    if vals.itemsize != 4:
        raise AssertionError('Unexpected f32 storage size')
    if os.sys.byteorder != 'little':
        vals.byteswap()
    with DATA_FILE.open('wb') as f:
        vals.tofile(f)
    return math.sqrt(sumsq)


def rust_sources():
    result = []
    for p in HOME.rglob('*.rs'):
        parts = p.parts
        if '.cargo' in parts or 'target' in parts:
            continue
        result.append(p)
    return result


def existing_executables():
    result = []
    for p in HOME.rglob('*'):
        if not p.is_file() or not os.access(p, os.X_OK) or not is_elf(p):
            continue
        parts = p.parts
        if '.cargo' in parts or 'deps' in parts or 'build' in parts or 'incremental' in parts:
            continue
        result.append(p)
    return result


def compile_submitted_rust(sources):
    cargo_files = [p for p in HOME.rglob('Cargo.toml') if '.cargo' not in p.parts and 'target' not in p.parts]
    preferred = HOME / 'feature_processor/Cargo.toml'
    if preferred in cargo_files:
        cargo_files.remove(preferred)
        cargo_files.insert(0, preferred)

    for manifest in cargo_files:
        target = Path('/tmp/verifier-cargo-target')
        shutil.rmtree(target, ignore_errors=True)
        env = os.environ.copy()
        env['CARGO_TARGET_DIR'] = str(target)
        try:
            raw = subprocess.check_output(
                ['cargo', 'metadata', '--no-deps', '--format-version', '1', '--manifest-path', str(manifest)],
                env=env, timeout=30, stderr=subprocess.DEVNULL)
            metadata = json.loads(raw)
            subprocess.run(
                ['cargo', 'build', '--release', '--quiet', '--manifest-path', str(manifest)],
                env=env, check=True, timeout=180)
        except (subprocess.SubprocessError, json.JSONDecodeError):
            continue

        bins = []
        for package in metadata.get('packages', []):
            for target_info in package.get('targets', []):
                if 'bin' in target_info.get('kind', []):
                    p = target / 'release' / target_info['name']
                    if p.is_file() and is_elf(p):
                        bins.append(p)
        if bins:
            return bins

    ordered = sorted(sources, key=lambda p: (p.name != 'main.rs', len(p.parts), str(p)))
    compiled = []
    for index, source in enumerate(ordered):
        output = Path(f'/tmp/submitted-rust-{index}')
        try:
            subprocess.run(['rustc', '-O', str(source), '-o', str(output)], cwd=str(source.parent),
                           check=True, timeout=120, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except subprocess.SubprocessError:
            continue
        if output.is_file() and is_elf(output):
            compiled.append(output)
    return compiled


# Preserve the original checks against the result left by the agent.
validate_metrics(ORIGINAL_EXPECTED)

sources = rust_sources()
assert sources, 'No submitted Rust source file was found under /home/user.'

# A pre-existing native artifact is required, showing that the submitted program was compiled.
existing = existing_executables()
assert existing, 'No compiled executable was found under /home/user.'

original_data = DATA_FILE.read_bytes()
assert len(original_data) == 4_000_000, 'features.bin must contain exactly 1,000,000 f32 values.'
selected_existing = None
selected_compiled = None
try:
    # Execute a pre-existing artifact on an unpredictable full-size input.
    expected_a = write_random_input()
    for executable in existing:
        try:
            run_and_validate(executable, expected_a)
            selected_existing = executable
            break
        except (AssertionError, OSError, subprocess.SubprocessError):
            continue
    assert selected_existing is not None, 'No compiled submitted executable correctly processed a changed features.bin.'

    # Compile the submitted Rust source independently and exercise that Rust program too.
    compiled = compile_submitted_rust(sources)
    assert compiled, 'The submitted Rust source could not be compiled.'
    expected_b = write_random_input()
    for executable in compiled:
        try:
            run_and_validate(executable, expected_b)
            selected_compiled = executable
            break
        except (AssertionError, OSError, subprocess.SubprocessError):
            continue
    assert selected_compiled is not None, 'The compiled Rust source did not compute the norm from features.bin.'
finally:
    DATA_FILE.write_bytes(original_data)

# Leave the required final metrics for the original data and re-apply the original value checks.
assert selected_compiled is not None
run_and_validate(selected_compiled, ORIGINAL_EXPECTED)
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
