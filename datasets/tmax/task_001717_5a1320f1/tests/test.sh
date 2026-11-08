#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import difflib
import os
import pathlib
import secrets
import string
import subprocess
import tempfile

import pytest

PROJECT = pathlib.Path('/home/user/auditor')
BINARY = PROJECT / 'target/release/side_channel_auditor'


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, text=True, capture_output=True, **kwargs)


def make_video(path, token):
    bits = ''.join(f'{ord(ch):08b}' for ch in token)
    raw_path = pathlib.Path(str(path) + '.raw')
    with open(raw_path, 'wb') as raw:
        for bit in bits:
            value = 255 if bit == '1' else 0
            raw.write(bytes([value]) * (100 * 100 * 3))

    try:
        run([
            'ffmpeg', '-loglevel', 'error', '-y',
            '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', '100x100', '-r', '10',
            '-i', str(raw_path), '-c:v', 'libx264', '-crf', '0',
            '-pix_fmt', 'yuv444p', str(path),
        ], timeout=60)
    finally:
        raw_path.unlink(missing_ok=True)


def extract(video):
    result = run([str(BINARY), str(video)], cwd=str(PROJECT), timeout=60)
    return result.stdout.strip()


def test_token_extraction_accuracy():
    target_file = '/home/user/token.txt'
    assert os.path.isfile(target_file), f'Output file {target_file} does not exist.'

    with open(target_file, 'r') as f:
        extracted_token = f.read().strip()

    reference_token = 'SEC{0x4F}'
    ratio = difflib.SequenceMatcher(None, reference_token, extracted_token).ratio()
    threshold = 1.0
    assert ratio >= threshold, (
        f'Token extraction accuracy too low. Expected ratio >= {threshold}, '
        f"but got {ratio}. Extracted token: '{extracted_token}'"
    )


def test_sources_build_and_binary_behavior():
    analyzer = PROJECT / 'src/analyzer.rs'
    main = PROJECT / 'src/main.rs'
    cargo = PROJECT / 'Cargo.toml'

    assert cargo.is_file(), 'Cargo.toml is missing.'
    assert analyzer.is_file(), 'Translated Rust module src/analyzer.rs is missing.'
    assert main.is_file(), 'src/main.rs is missing.'

    analyzer_text = analyzer.read_text()
    main_text = main.read_text()
    combined = analyzer_text + '\n' + main_text
    assert 'TODO' not in combined, 'The Rust implementation still contains a TODO.'
    assert 'fn extract_token' in analyzer_text, 'src/analyzer.rs does not implement extract_token.'
    assert 'mod analyzer' in main_text, 'src/main.rs does not include the analyzer module.'
    assert 'extract_token' in main_text, 'src/main.rs does not invoke the translated extraction logic.'

    BINARY.unlink(missing_ok=True)
    build = subprocess.run(
        ['cargo', 'build', '--release', '--manifest-path', str(cargo)],
        cwd=str(PROJECT), text=True, capture_output=True, timeout=300
    )
    assert build.returncode == 0, f'cargo build --release failed:\n{build.stdout}\n{build.stderr}'
    assert BINARY.is_file(), f'Release binary was not produced at {BINARY}.'
    assert os.access(BINARY, os.X_OK), 'Release artifact is not executable.'
    with open(BINARY, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'Release artifact is not an ELF executable.'

    assert extract('/app/auth_feed.mp4') == 'SEC{0x4F}', 'Binary failed on the supplied webcam feed.'

    alphabet = string.hexdigits[:16]
    generated_tokens = [
        'TST{' + ''.join(secrets.choice(alphabet) for _ in range(4)) + '}',
        'AUD{' + ''.join(secrets.choice(alphabet) for _ in range(8)) + '}',
    ]
    with tempfile.TemporaryDirectory() as td:
        for index, expected in enumerate(generated_tokens):
            video = pathlib.Path(td) / f'challenge-{index}.mp4'
            make_video(video, expected)
            actual = extract(video)
            assert actual == expected, (
                f'Binary did not analyze generated video {index}: '
                f'expected {expected!r}, got {actual!r}'
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
