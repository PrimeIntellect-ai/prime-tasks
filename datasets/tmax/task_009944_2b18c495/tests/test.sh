#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import subprocess
from pathlib import Path

import h5py
import numpy as np

HOME = Path('/home/user')
H5_PATH = HOME / 'spectrogram.h5'
OUTPUT_PATH = HOME / 'statistics.txt'
BACKUP_PATH = Path('/tmp/original_spectrogram.h5')
BUILD_DIR = Path('/tmp/spectrogram_verifier_build')


def compile_candidates():
    sources = sorted(
        p for p in HOME.rglob('*')
        if p.is_file() and p.suffix.lower() in {'.cpp', '.cc', '.cxx'}
    )
    assert sources, 'No C++ source file was found under /home/user.'

    for source in sources:
        text = source.read_text(errors='ignore').lower()
        assert 'eigen' not in text and 'armadillo' not in text, (
            f'External analytical library referenced by {source}'
        )

    BUILD_DIR.mkdir(parents=True, exist_ok=True)
    command_sets = [[source] for source in sources]
    if len(sources) > 1:
        command_sets.append(sources)

    binaries = []
    for index, source_set in enumerate(command_sets):
        binary = BUILD_DIR / f'candidate_{index}'
        result = subprocess.run(
            ['h5c++', '-std=c++17', '-O2', *map(str, source_set), '-o', str(binary)],
            cwd=str(HOME), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, timeout=90
        )
        if result.returncode == 0 and binary.is_file():
            binaries.append(binary)

    assert binaries, 'The submitted C++ source could not be compiled with h5c++.'
    return binaries


def restore_original():
    shutil.copy2(BACKUP_PATH, H5_PATH)


def run_binary(binary):
    if OUTPUT_PATH.exists():
        OUTPUT_PATH.unlink()
    result = subprocess.run(
        ['runuser', '-u', 'user', '--', str(binary)],
        cwd=str(HOME), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=30
    )
    assert result.returncode == 0, (
        f'Compiled tool exited with status {result.returncode}: {result.stderr}'
    )
    assert OUTPUT_PATH.is_file(), (
        'The compiled tool did not create /home/user/statistics.txt.'
    )


def read_output():
    with open(OUTPUT_PATH, 'r') as f:
        return f.read().strip().splitlines()


def assert_original_output():
    # Preserve the original verifier's exact output assertions.
    file_path = '/home/user/statistics.txt'
    assert os.path.isfile(file_path), (
        f'Output file {file_path} does not exist. The program may not have run '
        'or failed to write the output.'
    )

    with open(file_path, 'r') as f:
        content = f.read().strip().splitlines()

    assert len(content) == 2, (
        f'Output file {file_path} should contain exactly two lines, but found '
        f'{len(content)} lines.'
    )
    expected_mean_line = 'Global Mean: 61.75'
    expected_variance_line = 'Global Variance: 833.25'
    assert content[0].strip() == expected_mean_line, (
        f"First line of output is incorrect. Expected '{expected_mean_line}', "
        f"got '{content[0].strip()}'."
    )
    assert content[1].strip() == expected_variance_line, (
        f"Second line of output is incorrect. Expected '{expected_variance_line}', "
        f"got '{content[1].strip()}'."
    )


def write_hidden_dataset(trial):
    rng = np.random.default_rng(secrets.randbits(128))
    data = rng.normal(loc=17.0 - 9.0 * trial, scale=23.0 + trial, size=(100, 50))
    data += np.arange(100, dtype=np.float64)[:, None] * (0.37 + trial * 0.11)
    data += np.arange(50, dtype=np.float64)[None, :] * (-0.19 + trial * 0.07)
    data = np.asarray(data, dtype=np.float64)
    with h5py.File(H5_PATH, 'w') as handle:
        handle.create_dataset('signal', data=data, dtype='f8')

    row_means = [sum(float(x) for x in row) / 50.0 for row in data]
    global_mean = sum(row_means) / 100.0
    variance = sum((x - global_mean) ** 2 for x in row_means) / 100.0
    return [
        f'Global Mean: {global_mean:.2f}',
        f'Global Variance: {variance:.2f}',
    ]


def candidate_performs_required_work(binary):
    try:
        restore_original()
        run_binary(binary)
        assert_original_output()

        for trial in range(2):
            expected = write_hidden_dataset(trial)
            run_binary(binary)
            actual = read_output()
            assert len(actual) == 2, 'Output must contain exactly two lines.'
            assert [line.strip() for line in actual] == expected, (
                f'Incorrect result for a verifier-generated HDF5 dataset: '
                f'expected {expected}, got {actual}'
            )
        return True
    except (AssertionError, subprocess.SubprocessError, OSError):
        return False
    finally:
        restore_original()


def test_compiled_cpp_tool_reads_and_processes_hdf5():
    shutil.copy2(H5_PATH, BACKUP_PATH)
    binaries = compile_candidates()
    selected = None
    try:
        for binary in binaries:
            if candidate_performs_required_work(binary):
                selected = binary
                break
        assert selected is not None, (
            'No submitted C++ program both reproduced the required original '
            'statistics and correctly processed verifier-generated datasets.'
        )

        # Leave the required output corresponding to the instructed input.
        restore_original()
        run_binary(selected)
        assert_original_output()
    finally:
        restore_original()

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
