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

DETECTOR = "/home/user/detector"
SOURCE = "/home/user/detector.c"


def traced_run(executable, wav_path):
    trace_path = tempfile.mktemp(prefix="detector-trace-", suffix=".log")
    try:
        result = subprocess.run(
            ["strace", "-f", "-qq", "-e", "trace=process", "-o", trace_path,
             executable, wav_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        with open(trace_path, "r", errors="replace") as f:
            trace = f.read()
        exec_calls = re.findall(r"\bexecve\(", trace)
        assert len(exec_calls) == 1, (
            f"{executable} invoked an external executable while processing {wav_path}"
        )
        return result
    finally:
        try:
            os.unlink(trace_path)
        except FileNotFoundError:
            pass


def make_wav(path, chunks):
    body = bytearray(b"WAVE")
    for chunk_id, declared_size, payload in chunks:
        assert len(chunk_id) == 4
        body.extend(chunk_id)
        body.extend(struct.pack("<I", declared_size))
        body.extend(payload)
    with open(path, "wb") as f:
        f.write(b"RIFF")
        f.write(struct.pack("<I", len(body)))
        f.write(body)


def classify(executable, path, expected):
    result = traced_run(executable, path)
    assert result.returncode == expected, (
        f"{executable} returned {result.returncode} for {path}; expected {expected}. "
        f"stderr: {result.stderr.decode(errors='replace')}"
    )


def test_detector_exists_and_executable():
    assert os.path.isfile(DETECTOR), f"Detector binary not found at {DETECTOR}"
    assert os.access(DETECTOR, os.X_OK), f"Detector binary at {DETECTOR} is not executable"
    with open(DETECTOR, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Detector must be a compiled executable"

    assert os.path.isfile(SOURCE), f"C source not found at {SOURCE}"
    with open(SOURCE, "rb") as f:
        assert b"\x00" not in f.read(), "detector.c is not a text C source file"


def test_detector_against_corpora():
    clean_corpus_dir = "/app/corpus/clean"
    evil_corpus_dir = "/app/corpus/evil"

    assert os.path.isdir(clean_corpus_dir), f"Clean corpus dir not found: {clean_corpus_dir}"
    assert os.path.isdir(evil_corpus_dir), f"Evil corpus dir not found: {evil_corpus_dir}"

    clean_files = [os.path.join(clean_corpus_dir, f) for f in os.listdir(clean_corpus_dir)
                   if os.path.isfile(os.path.join(clean_corpus_dir, f))]
    evil_files = [os.path.join(evil_corpus_dir, f) for f in os.listdir(evil_corpus_dir)
                  if os.path.isfile(os.path.join(evil_corpus_dir, f))]

    assert len(clean_files) > 0, "No files found in clean corpus"
    assert len(evil_files) > 0, "No files found in evil corpus"

    clean_failed = []
    for clean_file in clean_files:
        result = traced_run(DETECTOR, clean_file)
        if result.returncode != 0:
            clean_failed.append(os.path.basename(clean_file))

    evil_failed = []
    for evil_file in evil_files:
        result = traced_run(DETECTOR, evil_file)
        if result.returncode != 1:
            evil_failed.append(os.path.basename(evil_file))

    errors = []
    if evil_failed:
        errors.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed: {', '.join(evil_failed)}")
    if clean_failed:
        errors.append(f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failed)}")
    assert not errors, "\n".join(errors)


def test_source_and_detector_on_generated_inputs():
    build_dir = tempfile.mkdtemp(prefix="detector-build-")
    rebuilt = os.path.join(build_dir, "detector-from-source")
    compile_result = subprocess.run(
        ["gcc", "-std=c11", "-O2", "-o", rebuilt, SOURCE],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert compile_result.returncode == 0, (
        "detector.c did not compile as C:\n" +
        compile_result.stderr.decode(errors="replace")
    )

    audio_dir = tempfile.mkdtemp(prefix="wav-cases-")
    fmt_payload = b"\x01\x00\x01\x00\x44\xac\x00\x00\x88\x58\x01\x00\x02\x00\x10\x00"
    cases = []

    def add_case(expected, chunks):
        path = os.path.join(audio_dir, secrets.token_hex(12) + ".bin")
        make_wav(path, chunks)
        cases.append((path, expected))

    add_case(0, [(b"fmt ", 16, fmt_payload), (b"data", 0, b"")])
    add_case(0, [(b"JUNK", 7, b"abcdefg"), (b"fmt ", 16, fmt_payload),
                 (b"data", 0, b"")])
    add_case(0, [(b"fmt ", 16, fmt_payload), (b"LOOP", 4, b"safe"),
                 (b"data", 0, b"")])
    add_case(1, [(b"fmt ", 16, fmt_payload), (b"LOOP", 0xFFFFFFFF, b"")])
    add_case(1, [(b"ABCD", 5, b"12345"), (b"data", 3, b"xyz"),
                 (b"LOOP", 0xFFFFFFFF, b"")])

    random.SystemRandom().shuffle(cases)
    for executable in (DETECTOR, rebuilt):
        for path, expected in cases:
            classify(executable, path, expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
