#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import re
import subprocess
from pathlib import Path

import matplotlib.image as mpimg
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, filtfilt, stft

HOME = Path('/home/user')
OUTPUTS = [
    HOME / 'clean_squiggle.wav',
    HOME / 'features.npy',
    HOME / 'alignment_pos.txt',
    HOME / 'spectrogram_plot.png',
]


def find_artifacts():
    py_files = []
    sh_files = []
    tokens = ('clean_squiggle.wav', 'features.npy', 'alignment_pos.txt',
              'spectrogram_plot.png', 'raw_squiggle.wav', 'candidate.txt',
              'reference.fasta')
    for path in HOME.rglob('*'):
        if not path.is_file() or path.is_symlink():
            continue
        if path.suffix not in ('.py', '.sh'):
            continue
        try:
            text = path.read_text(errors='replace')
        except OSError:
            continue
        if any(token in text for token in tokens):
            (py_files if path.suffix == '.py' else sh_files).append(path)
    assert py_files or sh_files, 'No executable pipeline/source artifact was found in /home/user'
    return sorted(py_files), sorted(sh_files)


def run_pipeline(required):
    py_files, sh_files = find_artifacts()
    env = os.environ.copy()
    env['HOME'] = str(HOME)

    # Prefer a shell orchestrator when one exists and produces all requested files.
    for path in sh_files:
        subprocess.run(['bash', str(path)], cwd=str(HOME), env=env,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                       text=True, timeout=120, check=False)
    if all(Path(p).is_file() for p in required):
        return

    # Split Python pipelines may depend on one another, so allow a few passes.
    for _ in range(3):
        for path in py_files:
            subprocess.run(['python3', str(path)], cwd=str(HOME), env=env,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           text=True, timeout=120, check=False)
        if all(Path(p).is_file() for p in required):
            return
    missing = [str(p) for p in required if not Path(p).is_file()]
    raise AssertionError(f'Pipeline did not generate required outputs: {missing}')


def check_parallel_and_plot_source():
    py_files, _ = find_artifacts()
    imported_parallel = False
    process_constructor = False
    dispatch_call = False
    heatmap_from_features = False

    for path in py_files:
        text = path.read_text(errors='replace')
        try:
            tree = ast.parse(text, filename=str(path))
        except SyntaxError:
            continue

        names = set()
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                for alias in node.names:
                    names.add(alias.name)
            elif isinstance(node, ast.ImportFrom) and node.module:
                names.add(node.module)
            elif isinstance(node, ast.Call):
                func = node.func
                if isinstance(func, ast.Name):
                    call_name = func.id
                elif isinstance(func, ast.Attribute):
                    call_name = func.attr
                else:
                    call_name = ''
                if call_name in ('Pool', 'Process', 'ProcessPoolExecutor'):
                    process_constructor = True
                if call_name in ('map', 'starmap', 'imap', 'imap_unordered',
                                 'submit', 'start'):
                    dispatch_call = True
                if call_name in ('imshow', 'matshow', 'pcolormesh') and 'features.npy' in text:
                    heatmap_from_features = True

        if any(name == 'multiprocessing' or name.startswith('multiprocessing.') or
               name == 'concurrent.futures' for name in names):
            imported_parallel = True

    assert imported_parallel and process_constructor and dispatch_call, \
        'Feature extraction source does not implement process-based parallel execution'
    assert heatmap_from_features, \
        'Plotting source does not render features.npy as a heatmap'


def expected_sw_start(reference, candidate):
    rows = len(candidate) + 1
    cols = len(reference) + 1
    scores = np.zeros((rows, cols), dtype=np.int32)
    best_score = 0
    best_i = best_j = 0
    for i in range(1, rows):
        for j in range(1, cols):
            diag = scores[i - 1, j - 1] + (3 if candidate[i - 1] == reference[j - 1] else -1)
            up = scores[i - 1, j] - 2
            left = scores[i, j - 1] - 2
            value = max(0, diag, up, left)
            scores[i, j] = value
            if value > best_score:
                best_score = value
                best_i, best_j = i, j

    i, j = best_i, best_j
    while i > 0 and j > 0 and scores[i, j] > 0:
        value = scores[i, j]
        diag_score = 3 if candidate[i - 1] == reference[j - 1] else -1
        if value == scores[i - 1, j - 1] + diag_score:
            i -= 1
            j -= 1
        elif value == scores[i - 1, j] - 2:
            i -= 1
        elif value == scores[i, j - 1] - 2:
            j -= 1
        else:
            break
    return j


def write_alignment_fixture(reference, candidate):
    Path('/app/data/reference.fasta').write_text('>dynamic_reference\n' + reference + '\n')
    Path('/app/data/candidate.txt').write_text(candidate + '\n')


def read_position():
    path = HOME / 'alignment_pos.txt'
    content = path.read_text().strip()
    assert re.fullmatch(r'[0-9]+', content), f'Invalid alignment position: {content!r}'
    return int(content)


def validate_signal_features_and_plot():
    raw_rate, raw = wavfile.read('/app/audio/raw_squiggle.wav')
    out_rate, cleaned = wavfile.read(HOME / 'clean_squiggle.wav')
    assert raw_rate == 8000 and out_rate == 8000
    assert raw.ndim == 1 and cleaned.ndim == 1
    assert cleaned.dtype == np.int16, 'Clean audio must be 16-bit PCM'
    assert cleaned.shape == raw.shape

    b, a = butter(4, 1500 / (0.5 * raw_rate), btype='low')
    expected_audio = np.int16(np.clip(filtfilt(b, a, raw), -32768, 32767))
    mse = np.mean((cleaned.astype(np.float64) - expected_audio.astype(np.float64)) ** 2)
    assert mse < 5.0, f'Denoised-audio MSE is too high: {mse}'

    features = np.load(HOME / 'features.npy', allow_pickle=False)
    _, _, expected_features = stft(cleaned, fs=out_rate, nperseg=256, noverlap=128)
    expected_features = np.abs(expected_features)
    assert features.ndim == 2
    assert features.shape == expected_features.shape, \
        f'Wrong STFT shape: {features.shape}, expected {expected_features.shape}'
    assert np.all(np.isfinite(features)) and np.all(features >= 0)
    assert np.allclose(features, expected_features, rtol=1e-5, atol=5e-2), \
        'features.npy does not contain the required STFT magnitude values'

    plot_path = HOME / 'spectrogram_plot.png'
    with plot_path.open('rb') as f:
        assert f.read(8) == b'\x89PNG\r\n\x1a\n', 'Plot is not a PNG file'
    image = mpimg.imread(plot_path)
    assert image.ndim in (2, 3) and image.shape[0] > 10 and image.shape[1] > 10
    visible = image[..., :3] if image.ndim == 3 and image.shape[2] >= 3 else image
    assert np.isfinite(visible).all() and float(np.std(visible)) > 0.01, \
        'Spectrogram PNG has no meaningful visual variation'


def test_complete_reproducible_pipeline():
    reference_path = Path('/app/data/reference.fasta')
    candidate_path = Path('/app/data/candidate.txt')
    original_reference = reference_path.read_bytes()
    original_candidate = candidate_path.read_bytes()

    try:
        check_parallel_and_plot_source()

        for output in OUTPUTS:
            output.unlink(missing_ok=True)
        run_pipeline(OUTPUTS)
        validate_signal_features_and_plot()
        assert read_position() == 42

        rng = np.random.default_rng(731942)
        alphabet = np.array(list('ACGT'))
        candidate = ''.join(rng.choice(alphabet, size=24))
        background = ''.join(rng.choice(alphabet, size=95))

        variants = []
        variants.append((background[:17] + candidate + background[17:], candidate))

        mismatch = list(candidate)
        for index in (5, 11, 18):
            mismatch[index] = next(base for base in 'ACGT' if base != mismatch[index])
        variants.append((background[:31] + ''.join(mismatch) + background[31:], candidate))

        deleted = candidate[:9] + candidate[10:]
        variants.append((background[:46] + deleted + background[46:], candidate))

        for reference, query in variants:
            expected = expected_sw_start(reference, query)
            (HOME / 'alignment_pos.txt').unlink(missing_ok=True)
            write_alignment_fixture(reference, query)
            run_pipeline([HOME / 'alignment_pos.txt'])
            assert read_position() == expected, \
                'Alignment implementation failed a dynamically generated Smith-Waterman case'
    finally:
        reference_path.write_bytes(original_reference)
        candidate_path.write_bytes(original_candidate)

    for output in OUTPUTS:
        output.unlink(missing_ok=True)
    run_pipeline(OUTPUTS)
    validate_signal_features_and_plot()
    assert read_position() == 42
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
