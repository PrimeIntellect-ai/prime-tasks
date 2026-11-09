#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import numpy as np
import scipy.io.wavfile as wav
import h5py

PROJECT = '/home/user/acoustic_analysis'
INPUT = '/app/stress_test.wav'
OUTPUT = '/home/user/cleaned.wav'
H5_OUTPUT = '/home/user/analysis.h5'
REFERENCE = '/tests/clean_reference.wav'
NFFT = 1024
HOP = 256


def stft(x, window, pad_tail=False):
    if pad_tail:
        frames = int(np.ceil(max(0, len(x) - NFFT) / HOP)) + 1
    else:
        frames = 1 + (len(x) - NFFT) // HOP
    out = np.empty((frames, NFFT // 2 + 1), dtype=np.float64)
    for i in range(frames):
        start = i * HOP
        frame = np.zeros(NFFT, dtype=np.float64)
        available = max(0, min(NFFT, len(x) - start))
        if available:
            frame[:available] = x[start:start + available]
        out[i] = np.abs(np.fft.rfft(frame * window))
    return out


def reconstruct(x, window, frames):
    output_len = (frames - 1) * HOP + NFFT
    y = np.zeros(output_len, dtype=np.float64)
    weight = np.zeros(output_len, dtype=np.float64)

    spec = np.empty((frames, NFFT // 2 + 1), dtype=np.complex128)
    magnitudes = np.empty((frames, NFFT // 2 + 1), dtype=np.float64)
    for i in range(frames):
        start = i * HOP
        frame = np.zeros(NFFT, dtype=np.float64)
        available = max(0, min(NFFT, len(x) - start))
        if available:
            frame[:available] = x[start:start + available]
        spec[i] = np.fft.rfft(frame * window)
        magnitudes[i] = np.abs(spec[i])

    std = np.std(magnitudes, axis=0)
    scores = np.convolve(std, np.ones(50, dtype=np.float64), mode='valid') / 50.0
    band_start = int(np.argmax(scores))
    mask = np.zeros(NFFT // 2 + 1, dtype=bool)
    mask[band_start:band_start + 50] = True
    spec[:, ~mask] = 0

    for i in range(frames):
        start = i * HOP
        frame = np.fft.irfft(spec[i], n=NFFT)
        y[start:start + NFFT] += frame * window
        weight[start:start + NFFT] += window * window

    good = weight > 1e-12
    y[good] /= weight[good]
    y[~good] = 0.0
    return y


def test_pipeline_outputs():
    assert os.path.isfile(os.path.join(PROJECT, 'Cargo.toml'), 'Missing Rust Cargo.toml.'
    assert os.path.isfile(os.path.join(PROJECT, 'src', 'main.rs')), 'Missing Rust src/main.rs.'
    assert os.path.isfile(REFERENCE), 'Verifier reference audio is unavailable.'

    # Outputs must be produced by executing the submitted Rust project now.
    for path in (OUTPUT, H5_OUTPUT):
        if os.path.exists(path):
            os.remove(path)
    result = subprocess.run(
        ['cargo', 'run', '--release', '--manifest-path', os.path.join(PROJECT, 'Cargo.toml')],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=300,
    )
    assert result.returncode == 0, 'Rust pipeline failed to run:\n' + result.stdout[-4000:]
    assert os.path.isfile(OUTPUT), f'Cleaned audio file {OUTPUT} does not exist.'
    assert os.path.isfile(H5_OUTPUT), f'HDF5 file {H5_OUTPUT} does not exist.'

    fs_in, input_pcm = wav.read(INPUT)
    assert input_pcm.dtype == np.int16 and input_pcm.ndim == 1, 'Unexpected input WAV format.'
    x = input_pcm.astype(np.float64) / 32768.0

    # Accept the two standard Hann endpoint conventions and either dropping or
    # zero-padding the final partial frame.
    windows = [
        np.hanning(NFFT),
        0.5 - 0.5 * np.cos(2.0 * np.pi * np.arange(NFFT) / NFFT),
    ]
    candidates = []
    for window in windows:
        for pad_tail in (False, True):
            expected = stft(x, window, pad_tail)
            candidates.append((expected, window, expected.shape[0]))

    with h5py.File(H5_OUTPUT, 'r') as f:
        assert 'spectrogram' in f, "Missing 'spectrogram' dataset in HDF5."
        assert 'std_dev' in f, "Missing 'std_dev' dataset in HDF5."
        spec_ds = f['spectrogram']
        std_ds = f['std_dev']
        assert spec_ds.ndim == 2, f'Spectrogram must be 2D, got shape {spec_ds.shape}'
        assert std_ds.ndim == 1, f'std_dev must be 1D, got shape {std_ds.shape}'
        assert spec_ds.dtype == np.dtype('float64'), 'spectrogram must contain 64-bit floats.'
        assert std_ds.dtype == np.dtype('float64'), 'std_dev must contain 64-bit floats.'
        spec = spec_ds[:]
        std = std_ds[:]

    assert spec.shape[1:] == (NFFT // 2 + 1,), f'Wrong spectrogram shape: {spec.shape}'
    assert std.shape == (NFFT // 2 + 1,), f'Wrong std_dev shape: {std.shape}'
    assert np.all(np.isfinite(spec)) and np.all(spec >= 0), 'Spectrogram has invalid magnitudes.'
    assert np.all(np.isfinite(std)) and np.all(std >= 0), 'std_dev has invalid values.'

    best = None
    for expected, window, frames in candidates:
        if expected.shape != spec.shape:
            continue
        denom = float(np.sum(expected * expected))
        scale = float(np.sum(spec * expected) / denom)
        if scale <= 0:
            continue
        rel_error = float(np.linalg.norm(spec - scale * expected) / np.linalg.norm(scale * expected))
        if best is None or rel_error < best[0]:
            best = (rel_error, expected, window, frames)
    assert best is not None, 'Spectrogram frame count does not match the requested STFT.'
    assert best[0] < 2e-5, f'Spectrogram does not contain the requested input STFT (relative error {best[0]:.3g}).'

    # Preserve the dimensionality checks while also verifying that std_dev is
    # actually computed from the exported unfiltered spectrogram.
    std_errors = []
    for ddof in (0, 1):
        expected_std = np.std(spec, axis=0, ddof=ddof)
        denom = max(float(np.linalg.norm(expected_std)), 1e-30)
        std_errors.append(float(np.linalg.norm(std - expected_std) / denom))
    assert min(std_errors) < 2e-5, 'std_dev is not the per-bin standard deviation of spectrogram.'

    fs_out, cleaned = wav.read(OUTPUT)
    assert fs_out == fs_in, f'Sample rates do not match: input {fs_in}, output {fs_out}'
    assert cleaned.dtype == np.int16 and cleaned.ndim == 1, 'cleaned.wav must remain mono 16-bit PCM.'
    assert len(cleaned) >= len(x) - NFFT, 'Cleaned audio is substantially shorter than the input.'
    cleaned_norm = cleaned.astype(np.float64) / 32768.0

    expected_audio = reconstruct(x, best[2], best[3])
    compare_len = min(len(cleaned_norm), len(expected_audio), len(x))
    processing_mse = float(np.mean((cleaned_norm[:compare_len] - expected_audio[:compare_len]) ** 2))
    assert processing_mse < 1e-5, f'cleaned.wav is not the requested 50-bin STFT reconstruction (MSE {processing_mse:.6g}).'

    # Retain the original clean-reference quality assertion, but the oracle is
    # supplied only at verification time and is not present in the agent image.
    fs_ref, ref = wav.read(REFERENCE)
    assert fs_ref == fs_out, f'Sample rates do not match: reference {fs_ref}, test {fs_out}'
    min_len = min(len(ref), len(cleaned))
    assert min_len > 0, 'Audio output is empty.'
    ref_norm = ref[:min_len].astype(np.float32) / 32768.0
    test_norm = cleaned[:min_len].astype(np.float32) / 32768.0
    mse = float(np.mean((ref_norm - test_norm) ** 2))
    threshold = 0.05
    assert mse <= threshold, f'Audio MSE is {mse:.6f}, which exceeds the threshold of {threshold}'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
