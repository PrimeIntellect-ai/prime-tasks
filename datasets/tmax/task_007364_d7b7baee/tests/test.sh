#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import stat
import subprocess
import tempfile

import h5py
import nbformat
import numpy as np

HOME = '/home/user'
DATA = os.path.join(HOME, 'data')
RUN = os.path.join(HOME, 'run_analysis.sh')
NOTEBOOK = os.path.join(HOME, 'fit_model.ipynb')
PEAKS = os.path.join(HOME, 'peaks.txt')
POSITIONS = os.path.join(HOME, 'positions.txt')
SLOPE = os.path.join(HOME, 'slope.txt')


def read_ints(path):
    with open(path, 'r') as f:
        lines = f.read().strip().split('\n')
    assert lines != [''], f'{path} is empty.'
    for line in lines:
        assert line.lstrip('-').isdigit(), f"Expected integer values in {path}, found '{line}'."
    return [int(line) for line in lines]


def expected_peaks(h5_path):
    with h5py.File(h5_path, 'r') as hf:
        assert 'raw_signals' in hf, 'raw_signals dataset is missing.'
        signals = np.asarray(hf['raw_signals'])
    assert signals.ndim == 2 and signals.shape[1] == 512
    return (np.argmax(np.abs(np.fft.fft(signals, axis=1))[:, 1:256], axis=1) + 1).tolist()


def expected_positions(fasta_path):
    sequences = []
    current = []
    with open(fasta_path, 'r') as f:
        for raw in f:
            line = raw.strip()
            if not line:
                continue
            if line.startswith('>'):
                if current:
                    sequences.append(''.join(current))
                current = []
            else:
                current.append(line)
    if current:
        sequences.append(''.join(current))
    return [seq.find('GATTACA') for seq in sequences]


def expected_slope(peaks, positions):
    kept = [(x, y) for x, y in zip(peaks, positions) if y != -1]
    assert len(kept) >= 2
    x = np.asarray([v[0] for v in kept], dtype=float)
    y = np.asarray([v[1] for v in kept], dtype=float)
    design = np.column_stack([np.ones(len(x)), x])
    return round(float(np.linalg.lstsq(design, y, rcond=None)[0][1]), 3)


def read_slope():
    assert os.path.isfile(SLOPE), f'{SLOPE} is missing.'
    with open(SLOPE, 'r') as f:
        content = f.read().strip()
    try:
        return float(content)
    except ValueError:
        assert False, f"Could not parse '{content}' as a float in {SLOPE}."


def remove_outputs():
    for path in (PEAKS, POSITIONS, SLOPE):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def execute_pipeline(timeout=240):
    subprocess.run([RUN], cwd=HOME, check=True, timeout=timeout,
                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)


def check_outputs_against_inputs():
    peaks = expected_peaks(os.path.join(DATA, 'signals.h5'))
    positions = expected_positions(os.path.join(DATA, 'reads.fasta'))
    assert read_ints(PEAKS) == peaks, 'peaks.txt does not match FFT peaks from signals.h5.'
    assert read_ints(POSITIONS) == positions, 'positions.txt does not match the first primer occurrences in reads.fasta.'
    actual = read_slope()
    wanted = expected_slope(peaks, positions)
    assert abs(actual - wanted) <= 0.00051, f'Expected rounded slope {wanted:.3f}, found {actual}.'


def write_challenge_inputs():
    frequencies = [13, 21, 34, 47, 58, 72, 83, 96]
    signals = []
    positions = [19, -1, 73, 101, 128, 157, -1, 211]
    t = np.arange(512)
    for i, frequency in enumerate(frequencies):
        signals.append(2.0 * np.sin(2 * np.pi * frequency * t / 512) +
                       0.1 * np.cos(2 * np.pi * (frequency + 3 + i) * t / 512))
    with h5py.File(os.path.join(DATA, 'signals.h5'), 'w') as hf:
        hf.create_dataset('raw_signals', data=np.asarray(signals))
    with open(os.path.join(DATA, 'reads.fasta'), 'w') as f:
        for i, position in enumerate(positions):
            seq = list('C' * 300)
            if position >= 0:
                seq[position:position + 7] = list('GATTACA')
            f.write(f'>challenge_{i}\n{"".join(seq)}\n')


def inject_execution_sentinel():
    notebook = nbformat.read(NOTEBOOK, as_version=4)
    token = secrets.token_hex(24)
    token_path = os.path.join('/tmp', 'analysis_notebook_' + secrets.token_hex(12))
    source = f"with open({token_path!r}, 'w') as _f:\n    _f.write({token!r})"
    notebook.cells.append(nbformat.v4.new_code_cell(source=source))
    nbformat.write(notebook, NOTEBOOK)
    return token_path, token


def test_00_pipeline_behavior_and_execution():
    assert os.path.isfile(RUN), f'{RUN} is missing.'
    assert bool(os.stat(RUN).st_mode & stat.S_IXUSR), f'{RUN} is not executable.'
    assert os.path.isfile(NOTEBOOK), f'{NOTEBOOK} is missing.'
    notebook = nbformat.read(NOTEBOOK, as_version=4)
    assert any(cell.cell_type == 'code' for cell in notebook.cells), 'The notebook has no code cells.'

    backup_dir = tempfile.mkdtemp(prefix='pipeline-input-backup-')
    backup_h5 = os.path.join(backup_dir, 'signals.h5')
    backup_fasta = os.path.join(backup_dir, 'reads.fasta')
    shutil.copy2(os.path.join(DATA, 'signals.h5'), backup_h5)
    shutil.copy2(os.path.join(DATA, 'reads.fasta'), backup_fasta)
    token_path = None

    try:
        token_path, token = inject_execution_sentinel()
        write_challenge_inputs()
        remove_outputs()
        execute_pipeline()
        check_outputs_against_inputs()
        assert os.path.isfile(token_path), 'run_analysis.sh did not execute fit_model.ipynb.'
        with open(token_path, 'r') as f:
            assert f.read() == token, 'Notebook execution sentinel was not produced correctly.'

        # Execute the submitted notebook independently on derived feature files to
        # verify that the notebook itself performs filtering and OLS modeling.
        synthetic_peaks = [2, 5, 9, 14, 20, 27]
        synthetic_positions = [7, -1, 18, 31, 42, 55]
        with open(PEAKS, 'w') as f:
            f.write('\n'.join(map(str, synthetic_peaks)) + '\n')
        with open(POSITIONS, 'w') as f:
            f.write('\n'.join(map(str, synthetic_positions)) + '\n')
        try:
            os.remove(SLOPE)
        except FileNotFoundError:
            pass
        subprocess.run(['jupyter', 'nbconvert', '--to', 'notebook', '--execute',
                        '--inplace', NOTEBOOK], cwd=HOME, check=True, timeout=240,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        wanted = expected_slope(synthetic_peaks, synthetic_positions)
        actual = read_slope()
        assert abs(actual - wanted) <= 0.00051, (
            f'Notebook should write rounded slope {wanted:.3f} for independent inputs, found {actual}.')

        # Restore the supplied datasets and require the complete workflow to
        # produce its final deliverables from them as instructed.
        shutil.copy2(backup_h5, os.path.join(DATA, 'signals.h5'))
        shutil.copy2(backup_fasta, os.path.join(DATA, 'reads.fasta'))
        remove_outputs()
        execute_pipeline()
        check_outputs_against_inputs()
    finally:
        shutil.copy2(backup_h5, os.path.join(DATA, 'signals.h5'))
        shutil.copy2(backup_fasta, os.path.join(DATA, 'reads.fasta'))
        if token_path:
            try:
                os.remove(token_path)
            except FileNotFoundError:
                pass
        shutil.rmtree(backup_dir)


def test_run_analysis_exists_and_executable():
    path = '/home/user/run_analysis.sh'
    assert os.path.isfile(path), f'{path} is missing.'
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f'{path} is not executable.'


def test_peaks_file():
    path = '/home/user/peaks.txt'
    assert os.path.isfile(path), f'{path} is missing.'
    with open(path, 'r') as f:
        lines = f.read().strip().split('\n')
    assert len(lines) == 50, f'Expected 50 lines in {path}, found {len(lines)}.'
    for line in lines:
        assert line.lstrip('-').isdigit(), f"Expected integer values in {path}, found '{line}'."


def test_positions_file():
    path = '/home/user/positions.txt'
    assert os.path.isfile(path), f'{path} is missing.'
    with open(path, 'r') as f:
        lines = f.read().strip().split('\n')
    assert len(lines) == 50, f'Expected 50 lines in {path}, found {len(lines)}.'
    for line in lines:
        assert line.lstrip('-').isdigit(), f"Expected integer values in {path}, found '{line}'."


def test_notebook_exists():
    path = '/home/user/fit_model.ipynb'
    assert os.path.isfile(path), f'{path} is missing.'


def test_slope_file():
    path = '/home/user/slope.txt'
    assert os.path.isfile(path), f'{path} is missing.'
    with open(path, 'r') as f:
        content = f.read().strip()
    try:
        slope = float(content)
    except ValueError:
        assert False, f"Could not parse '{content}' as a float in {path}."
    assert abs(slope - 2.0) < 0.05, f'Expected slope to be around 2.000, found {slope}.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
