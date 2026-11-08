#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import struct
import subprocess
import tempfile
import zipfile

import pytest

SCRIPT_PATH = "/home/user/ingest_filter.py"
CLEAN_CORPUS = "/app/corpus/clean"
EVIL_CORPUS = "/app/corpus/evil"
TOKEN = "BlueFalcon99"


@pytest.fixture(scope="module")
def run_clean():
    out_dir = tempfile.mkdtemp()
    strace_log = tempfile.mktemp()
    cmd = [
        "strace", "-f", "-e", "trace=rename,renameat2", "-o", strace_log,
        "python3", SCRIPT_PATH, "--input-dir", CLEAN_CORPUS, "--output-dir", out_dir
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    yield out_dir, strace_log, result
    shutil.rmtree(out_dir, ignore_errors=True)
    if os.path.exists(strace_log):
        os.remove(strace_log)


@pytest.fixture(scope="module")
def run_evil():
    out_dir = tempfile.mkdtemp()
    cmd = [
        "python3", SCRIPT_PATH, "--input-dir", EVIL_CORPUS, "--output-dir", out_dir
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    yield out_dir, result
    shutil.rmtree(out_dir, ignore_errors=True)


def make_wav(audio_format=1, channels=2, sample_rate=44100, bits=16):
    block_align = channels * bits // 8
    byte_rate = sample_rate * block_align
    samples = b"\x00" * (block_align * 97)
    fmt = struct.pack("<HHIIHH", audio_format, channels, sample_rate,
                      byte_rate, block_align, bits)
    body = b"fmt " + struct.pack("<I", len(fmt)) + fmt
    body += b"data" + struct.pack("<I", len(samples)) + samples
    return b"RIFF" + struct.pack("<I", len(body) + 4) + b"WAVE" + body


def write_archive(path, *, token=TOKEN, metadata=True, wavs=1,
                  audio_format=1, channels=2, sample_rate=44100, bits=16):
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        if metadata:
            zf.writestr("metadata.txt", f"Token: {token}\nrandom payload: {secrets.token_hex(8)}\n")
        for i in range(wavs):
            name = "audio.wav" if i == 0 else f"extra_{i}.wav"
            zf.writestr(name, make_wav(audio_format, channels, sample_rate, bits))
        zf.writestr("payload.bin", secrets.token_bytes(73))


@pytest.fixture(scope="module")
def randomized_run():
    root = tempfile.mkdtemp(prefix="ingestion-case-")
    input_dir = os.path.join(root, secrets.token_hex(6))
    output_dir = os.path.join(root, secrets.token_hex(6))
    os.mkdir(input_dir)
    os.mkdir(output_dir)

    def new_name():
        return secrets.token_hex(12) + ".zip"

    accepted = set()
    for _ in range(4):
        name = new_name()
        write_archive(os.path.join(input_dir, name))
        accepted.add(name)

    invalid_specs = [
        {"token": "not-" + TOKEN},
        {"metadata": False},
        {"wavs": 0},
        {"wavs": 2},
        {"audio_format": 3},
        {"channels": 1},
        {"sample_rate": 48000},
        {"bits": 8},
    ]
    for spec in invalid_specs:
        write_archive(os.path.join(input_dir, new_name()), **spec)

    corrupt_name = new_name()
    corrupt_path = os.path.join(input_dir, corrupt_name)
    write_archive(corrupt_path)
    with open(corrupt_path, "r+b") as f:
        f.truncate(max(10, os.path.getsize(corrupt_path) // 2))

    garbage_name = new_name()
    with open(os.path.join(input_dir, garbage_name), "wb") as f:
        f.write(b"PK\x03\x04" + secrets.token_bytes(91))

    strace_log = os.path.join(root, "trace.log")
    cmd = [
        "strace", "-f", "-e", "trace=rename,renameat,renameat2", "-o", strace_log,
        "python3", SCRIPT_PATH, "--input-dir", input_dir, "--output-dir", output_dir
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    yield input_dir, output_dir, accepted, strace_log, result
    shutil.rmtree(root, ignore_errors=True)


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Ingestion script missing at {SCRIPT_PATH}"


def test_clean_corpus(run_clean):
    out_dir, strace_log, result = run_clean

    assert result.returncode == 0, f"Script failed on clean corpus with error: {result.stderr}"

    expected_files = set(f for f in os.listdir(CLEAN_CORPUS) if f.endswith('.zip'))
    output_files = set(f for f in os.listdir(out_dir) if f.endswith('.zip'))

    missing = expected_files - output_files
    modified = output_files - expected_files

    assert not missing, f"{len(missing)} of {len(expected_files)} clean files were incorrectly rejected. Missing: {missing}"
    assert not modified, f"Unexpected files generated in output directory: {modified}"

    for name in expected_files:
        with open(os.path.join(CLEAN_CORPUS, name), "rb") as src:
            source_bytes = src.read()
        with open(os.path.join(out_dir, name), "rb") as dst:
            output_bytes = dst.read()
        assert output_bytes == source_bytes, f"Copied archive {name} does not match its source"

    # Check atomic rename requirement
    assert os.path.exists(strace_log), "strace log was not created."
    with open(strace_log, 'r') as f:
        log_content = f.read()

    # We expect to see a rename operation from a .tmp file to a .zip file
    assert ".tmp" in log_content and ".zip" in log_content, (
        "Atomic rename requirement not met. No rename syscalls moving .tmp to .zip found in strace log."
    )


def test_evil_corpus(run_evil):
    out_dir, result = run_evil

    assert result.returncode == 0, f"Script failed on evil corpus with error: {result.stderr}"

    expected_evil_files = set(f for f in os.listdir(EVIL_CORPUS) if f.endswith('.zip'))
    output_files = set(f for f in os.listdir(out_dir) if f.endswith('.zip'))

    assert not output_files, f"{len(output_files)} of {len(expected_evil_files)} evil files bypassed the filter and were written to output: {output_files}"


def test_randomized_mixed_corpus(randomized_run):
    input_dir, output_dir, accepted, strace_log, result = randomized_run
    assert result.returncode == 0, f"Script failed on randomized corpus: {result.stderr}"

    actual = set(os.listdir(output_dir))
    assert actual == accepted, (
        f"Incorrect randomized-corpus result. Missing: {accepted - actual}; "
        f"unexpected: {actual - accepted}"
    )

    for name in accepted:
        with open(os.path.join(input_dir, name), "rb") as src:
            source_bytes = src.read()
        with open(os.path.join(output_dir, name), "rb") as dst:
            output_bytes = dst.read()
        assert output_bytes == source_bytes, f"Output {name} is not a byte-for-byte copy"
        with zipfile.ZipFile(os.path.join(output_dir, name)) as zf:
            assert zf.testzip() is None

    with open(strace_log, "r") as f:
        trace_lines = f.readlines()

    for name in accepted:
        destination = os.path.join(output_dir, name)
        matching = []
        for line in trace_lines:
            if "rename" not in line or " = 0" not in line:
                continue
            quoted = re.findall(r'"([^"\\]*(?:\\.[^"\\]*)*)"', line)
            if len(quoted) >= 2 and quoted[-1] == destination:
                matching.append(quoted[0])
        assert any(source.endswith(".tmp") for source in matching), (
            f"No successful atomic rename from a .tmp file produced {name}"
        )


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
