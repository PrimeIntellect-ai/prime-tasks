#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import secrets
import subprocess
import tempfile
import urllib.parse

import pytest

BINARY_PATH = "/home/user/telemetry_gate/target/release/telemetry_gate"
LEGACY_PATH = "/app/legacy_gate"
CLEAN_CORPUS_DIR = "/home/user/corpora/clean/"
EVIL_CORPUS_DIR = "/home/user/corpora/evil/"
BENCHMARK_RESULTS_FILE = "/home/user/benchmark_results.txt"
EXPECTED_BENCHMARK_STDOUT = "Benchmarking...\nBenchmark completed\n"


def run_gate(path):
    return subprocess.run([BINARY_PATH, path], capture_output=True, timeout=5)


def encoded_document(text):
    encoded = base64.b64encode(text.encode("utf-8")).decode("ascii")
    return {"payload": urllib.parse.quote(encoded, safe="")}


def test_rust_binary_exists_and_executable():
    assert os.path.isfile(BINARY_PATH), f"Rust binary not found at {BINARY_PATH}. Did you run 'cargo build --release'?"
    assert os.access(BINARY_PATH, os.X_OK), f"Rust binary at {BINARY_PATH} is not executable."
    with open(BINARY_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The submitted artifact is not an ELF executable."
    with open(BINARY_PATH, "rb") as submitted, open(LEGACY_PATH, "rb") as legacy:
        assert submitted.read() != legacy.read(), "The submitted binary must not be a copy of the legacy oracle."


def test_clean_corpus_accepted():
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Clean corpus directory missing at {CLEAN_CORPUS_DIR}"
    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    assert clean_files, f"No files found in {CLEAN_CORPUS_DIR}"
    failures = []
    for name in clean_files:
        if run_gate(os.path.join(CLEAN_CORPUS_DIR, name)).returncode != 0:
            failures.append(name)
    if failures:
        pytest.fail(f"{len(failures)} of {len(clean_files)} clean files rejected. Offending files: {failures[:5]}")


def test_evil_corpus_rejected():
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Evil corpus directory missing at {EVIL_CORPUS_DIR}"
    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    assert evil_files, f"No files found in {EVIL_CORPUS_DIR}"
    failures = []
    for name in evil_files:
        if run_gate(os.path.join(EVIL_CORPUS_DIR, name)).returncode == 0:
            failures.append(name)
    if failures:
        pytest.fail(f"{len(failures)} of {len(evil_files)} evil files bypassed. Offending files: {failures[:5]}")


def test_randomized_decoding_and_validation():
    nonce = secrets.token_hex(18)
    cases = [
        (f"ordinary telemetry {nonce}", 0),
        (f"prefix-{nonce}-<script>-suffix", 1),
        (f"prefix-{nonce}-DROP TABLE-suffix", 1),
        (f"prefix-{nonce}-admin=true-suffix", 1),
        (f"<Script> {nonce}", 0),
        (f"drop table {nonce}", 0),
        (f"admin=True {nonce}", 0),
        (f"{nonce} <scripture> DROP  TABLE administrator=true", 0),
        (f"{nonce}\nadmin=true\nDROP TABLE", 1),
    ]
    with tempfile.TemporaryDirectory(prefix=f"telemetry-{nonce}-") as directory:
        order = list(range(len(cases)))
        for index in order:
            text, expected = cases[index]
            path = os.path.join(directory, f"{secrets.token_hex(12)}.dat")
            with open(path, "w", encoding="utf-8") as f:
                json.dump(encoded_document(text), f)
            result = run_gate(path)
            if expected == 0:
                assert result.returncode == 0, f"Valid randomized payload was rejected: {text!r}"
            else:
                assert result.returncode != 0, f"Malicious randomized payload was accepted: {text!r}"


def test_invalid_inputs_are_rejected():
    malformed = [
        b"not json",
        b"{}",
        b'{"payload": 17}',
        b'{"payload":"%%%not-base64%%%"}',
        json.dumps({"payload": base64.b64encode(b"\xff\xfe").decode("ascii")}).encode("utf-8"),
    ]
    with tempfile.TemporaryDirectory(prefix=f"invalid-{secrets.token_hex(12)}-") as directory:
        for content in malformed:
            path = os.path.join(directory, secrets.token_hex(12))
            with open(path, "wb") as f:
                f.write(content)
            assert run_gate(path).returncode != 0, f"Malformed input was accepted: {content!r}"
    assert subprocess.run([BINARY_PATH], capture_output=True, timeout=5).returncode != 0


def test_benchmark_results():
    assert os.path.isfile(BENCHMARK_RESULTS_FILE), f"Benchmark results file missing at {BENCHMARK_RESULTS_FILE}"
    with open(BENCHMARK_RESULTS_FILE, "r", encoding="utf-8") as f:
        content = f.read()
    assert len(content.strip()) > 0, f"Benchmark results file {BENCHMARK_RESULTS_FILE} is empty."
    assert "Benchmark completed" in content, f"Benchmark results file {BENCHMARK_RESULTS_FILE} does not contain 'Benchmark completed'."
    assert content == EXPECTED_BENCHMARK_STDOUT, "benchmark_results.txt is not the exact stdout of the provided benchmark script."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
