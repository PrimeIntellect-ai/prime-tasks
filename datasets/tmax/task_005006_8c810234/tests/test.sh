#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import secrets
import struct
import subprocess
import tempfile
import pytest


def test_transcript():
    transcript_path = "/home/user/transcript.txt"
    assert os.path.exists(transcript_path), f"Missing required file: {transcript_path}"

    with open(transcript_path, "r") as f:
        content = f.read().strip().lower()

    # Remove punctuation just in case the student left some
    import string
    content = content.translate(str.maketrans('', '', string.punctuation))

    assert "the system is compromised" in content, f"Transcript does not contain the expected text. Found: {content}"


def test_sanitizer_executable():
    executable_path = "/home/user/wav_sanitizer"
    assert os.path.exists(executable_path), f"Missing executable: {executable_path}"
    assert os.access(executable_path, os.X_OK), f"File is not executable: {executable_path}"
    assert os.path.isfile(executable_path), f"Executable is not a regular file: {executable_path}"
    with open(executable_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "wav_sanitizer is not a compiled ELF executable"


def test_sanitizer_source():
    source_path = "/home/user/wav_sanitizer.c"
    assert os.path.isfile(source_path), f"Missing required C source: {source_path}"
    with open(source_path, "r", encoding="utf-8", errors="replace") as f:
        source = f.read()

    # Ignore comments when checking that assert.h and an assertion are actually present.
    code = re.sub(r"/\*.*?\*/|//[^\n]*", "", source, flags=re.DOTALL)
    assert re.search(r"#\s*include\s*[<\"]assert\.h[>\"]", code), "Source must include assert.h"
    assert re.search(r"\bassert\s*\(", code), "Source must use assertion-based validation"

    rebuilt = os.path.join(tempfile.mkdtemp(prefix="wav-build-"), "wav_sanitizer")
    result = subprocess.run(
        ["gcc", "-std=c11", "-O2", "-UNDEBUG", source_path, "-o", rebuilt],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"wav_sanitizer.c does not compile:\n{result.stderr}"
    os.environ["REBUILT_SANITIZER"] = rebuilt


def test_sanitizer_clean_corpus():
    executable_path = "/home/user/wav_sanitizer"
    clean_dir = "/app/corpus/clean/"

    assert os.path.exists(clean_dir), f"Clean corpus directory missing: {clean_dir}"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    assert len(clean_files) > 0, "No files found in clean corpus."

    failed_files = []
    for filepath in clean_files:
        result = subprocess.run([executable_path, filepath], capture_output=True)
        if result.returncode != 0:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean files were incorrectly rejected (exit code != 0): {', '.join(failed_files)}")


def test_sanitizer_evil_corpus():
    executable_path = "/home/user/wav_sanitizer"
    evil_dir = "/app/corpus/evil/"

    assert os.path.exists(evil_dir), f"Evil corpus directory missing: {evil_dir}"

    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    assert len(evil_files) > 0, "No files found in evil corpus."

    bypassed_files = []
    for filepath in evil_files:
        result = subprocess.run([executable_path, filepath], capture_output=True)
        if result.returncode != 1:
            bypassed_files.append(os.path.basename(filepath))

    if bypassed_files:
        pytest.fail(f"{len(bypassed_files)} of {len(evil_files)} evil files bypassed the sanitizer (exit code != 1): {', '.join(bypassed_files)}")


def make_pcm_wav(data, declared_data_size=None, riff=b"RIFF", wave=b"WAVE"):
    if declared_data_size is None:
        declared_data_size = len(data)
    return b"".join([
        riff,
        struct.pack("<I", 36 + len(data)),
        wave,
        b"fmt ",
        struct.pack("<I", 16),
        struct.pack("<HHIIHH", 1, 1, 44100, 88200, 2, 16),
        b"data",
        struct.pack("<I", declared_data_size),
        data,
    ])


def test_randomized_hidden_wav_cases():
    # Test both the submitted executable and a fresh build of the submitted source.
    rebuilt = os.environ.get("REBUILT_SANITIZER")
    assert rebuilt and os.path.exists(rebuilt), "Freshly compiled sanitizer is unavailable"

    case_dir = tempfile.mkdtemp(prefix="wav-cases-")
    cases = []

    def add_case(blob, expected):
        path = os.path.join(case_dir, secrets.token_hex(16))
        with open(path, "wb") as f:
            f.write(blob)
        cases.append((path, expected))

    # Each valid file is paired with an overflow file of exactly the same physical
    # length, so filename/path/size dispatch cannot distinguish the expected result.
    for _ in range(12):
        data_len = 2 * secrets.randbelow(2048)
        payload = os.urandom(data_len)
        add_case(make_pcm_wav(payload), 0)
        overflowing_size = 0xFFFFF000 + secrets.randbelow(0x1000)
        add_case(make_pcm_wav(payload, declared_data_size=overflowing_size), 1)

    # Corrupted signatures and truncated chunk metadata must also be rejected.
    payload = os.urandom(128)
    add_case(make_pcm_wav(payload, riff=b"RIFX"), 1)
    add_case(make_pcm_wav(payload, wave=b"WVAE"), 1)

    truncated = b"RIFF" + struct.pack("<I", 8) + b"WAVE" + b"data"
    add_case(truncated, 1)

    # A maximum odd chunk size overflows if padding is computed in 32 bits.
    padded_overflow = b"RIFF" + struct.pack("<I", 12) + b"WAVE" + b"JUNK" + struct.pack("<I", 0xFFFFFFFF)
    add_case(padded_overflow, 1)

    random.SystemRandom().shuffle(cases)
    for executable in ("/home/user/wav_sanitizer", rebuilt):
        failures = []
        for path, expected in cases:
            try:
                result = subprocess.run([executable, path], capture_output=True, timeout=2)
                actual = result.returncode
            except subprocess.TimeoutExpired:
                actual = "timeout"
            if actual != expected:
                failures.append((os.path.basename(path), expected, actual))
        assert not failures, f"Sanitizer failed randomized content-derived cases: {failures}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
