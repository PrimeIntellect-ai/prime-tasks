#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import hashlib
import subprocess
import tempfile
from pathlib import Path
from collections import defaultdict
import numpy as np
import scipy.io.wavfile as wavfile
import pytest


def get_sha256(path):
    hash_sha256 = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(4096), b""):
            hash_sha256.update(chunk)
    return hash_sha256.hexdigest()


def assert_original_inventory():
    """Verify that all files supplied in the storage pool remain intact."""
    storage_pool = Path('/app/storage_pool')
    assert storage_pool.exists() and storage_pool.is_dir(), "/app/storage_pool is missing."

    for i in range(1, 501):
        filepath = storage_pool / f'dummy_{i}.txt'
        assert filepath.exists() and filepath.is_file(), f"Required file is missing: {filepath}"
        expected = f"Dummy content {i}\n".encode()
        assert filepath.read_bytes() == expected, f"Required file was modified: {filepath}"

    reference = Path('/app/voicemail.wav')
    assert reference.exists() and reference.is_file(), "/app/voicemail.wav is missing."
    reference_checksum = get_sha256(reference)
    for i in range(1, 21):
        filepath = storage_pool / 'logs' / f'call_{i}.wav'
        assert filepath.exists() and filepath.is_file(), f"Required file is missing: {filepath}"
        assert get_sha256(filepath) == reference_checksum, f"Required audio file was modified: {filepath}"


def test_deduplication_hard_links():
    """Verify that all files with identical content share the same inode."""
    assert_original_inventory()
    storage_pool = Path('/app/storage_pool')

    content_to_inodes = defaultdict(set)
    content_to_files = defaultdict(list)

    for filepath in storage_pool.rglob('*'):
        if filepath.is_file():
            checksum = get_sha256(filepath)
            inode = filepath.stat().st_ino
            content_to_inodes[checksum].add(inode)
            content_to_files[checksum].append(str(filepath))

    for checksum, inodes in content_to_inodes.items():
        assert len(inodes) == 1, (
            f"Files with checksum {checksum} are not fully deduplicated into a single inode. "
            f"Found inodes {inodes} for files: {content_to_files[checksum]}"
        )


def test_manifest_generation():
    """Verify the manifest file format, sorting, and correctness."""
    assert_original_inventory()
    manifest_path = Path('/home/user/dedup_manifest.txt')
    assert manifest_path.exists(), "Manifest file /home/user/dedup_manifest.txt does not exist."

    storage_pool = Path('/app/storage_pool')

    # Collect ground truth unique inodes and their checksums
    unique_inodes = {}
    for filepath in storage_pool.rglob('*'):
        if filepath.is_file():
            inode = filepath.stat().st_ino
            if inode not in unique_inodes:
                unique_inodes[inode] = get_sha256(filepath)

    with open(manifest_path, 'r', encoding='utf-8') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == len(unique_inodes), (
        f"Manifest should have exactly {len(unique_inodes)} lines, but has {len(lines)}."
    )

    parsed_paths = []
    for line in lines:
        parts = line.split()
        assert len(parts) >= 2, f"Invalid manifest line format: '{line}'"
        checksum = parts[0]
        filepath = " ".join(parts[1:])
        parsed_paths.append(filepath)

        full_path = Path(filepath)
        assert full_path.exists(), f"Path in manifest does not exist: {filepath}"
        assert full_path.is_file(), f"Path in manifest is not a file: {filepath}"

        actual_checksum = get_sha256(full_path)
        assert checksum == actual_checksum, (
            f"Checksum mismatch for {filepath}: expected {actual_checksum}, got {checksum}"
        )

    # Check sorting by file path
    assert parsed_paths == sorted(parsed_paths), "Manifest is not sorted alphabetically by file paths."


def test_audio_compression_metric():
    """Verify compressed audio size, duration, and MSE metric."""
    ogg_path = Path('/home/user/compressed_audio.ogg')
    wav_path = Path('/app/voicemail.wav')

    assert ogg_path.exists(), "Compressed audio /home/user/compressed_audio.ogg does not exist."

    size_kb = os.path.getsize(ogg_path)
    assert size_kb < 150000, f"FAIL: File size {size_kb} bytes exceeds 150KB limit."

    # Convert OGG to WAV using ffmpeg to read with scipy
    with tempfile.NamedTemporaryFile(suffix='.wav') as temp_wav:
        try:
            subprocess.run(
                ['ffmpeg', '-y', '-i', str(ogg_path), temp_wav.name],
                check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            )
        except FileNotFoundError:
            pytest.fail("ffmpeg is required to test the OGG file but is not installed.")
        except subprocess.CalledProcessError:
            pytest.fail("Failed to convert OGG back to WAV using ffmpeg.")

        sr_orig, y_orig_int = wavfile.read(wav_path)
        sr_comp, y_comp_int = wavfile.read(temp_wav.name)

    assert sr_orig == 16000, f"Original audio sample rate was modified: {sr_orig}."
    assert len(y_orig_int) == 60 * sr_orig, "Original audio is no longer the required 60-second artifact."
    assert sr_comp == sr_orig, f"Compressed audio sample rate differs: {sr_comp} != {sr_orig}."
    assert len(y_comp_int) == len(y_orig_int), (
        f"Compressed audio must represent the full artifact: got {len(y_comp_int)} samples, "
        f"expected {len(y_orig_int)}."
    )

    # librosa normalizes 16-bit PCM to float32 in [-1, 1]
    def normalize_audio(y):
        if y.dtype == np.int16:
            return y.astype(np.float32) / 32768.0
        elif y.dtype == np.int32:
            return y.astype(np.float32) / 2147483648.0
        return y.astype(np.float32)

    y_orig = normalize_audio(y_orig_int)
    y_comp = normalize_audio(y_comp_int)

    if len(y_orig.shape) > 1:
        y_orig = np.mean(y_orig, axis=1)
    if len(y_comp.shape) > 1:
        y_comp = np.mean(y_comp, axis=1)

    min_len = min(len(y_orig), len(y_comp))
    y_orig = y_orig[:min_len]
    y_comp = y_comp[:min_len]

    mse = np.mean((y_orig - y_comp) ** 2)
    assert mse <= 0.005, f"FAIL: MSE exceeds threshold. Got {mse:.6f}, expected <= 0.005."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
