#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import secrets
import string
import subprocess
import tempfile
import wave

import pytest


def test_json_report():
    report_path = '/home/user/recovery_report.json'
    assert os.path.isfile(report_path), f"Report file not found at {report_path}"

    with open(report_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {report_path} is not valid JSON.")

    expected_keys = {"transcription", "crash_timestamp", "last_recovered_tx_id"}
    assert set(data) == expected_keys, f"Report must contain exactly {sorted(expected_keys)}"
    assert all(isinstance(data[k], str) for k in expected_keys), "All report values must be strings."

    # Keep the original transcription check.
    transcription = data["transcription"].lower()
    transcription_without_punctuation = transcription.translate(
        str.maketrans('', '', string.punctuation)
    )
    expected_phrase = "evacuation order authorized for sector seven"
    assert expected_phrase in transcription_without_punctuation, (
        f"Transcription does not contain expected phrase. Got: {data['transcription']}"
    )
    assert data["transcription"] == transcription, "Transcription must be lowercase."

    # Verify that the submitted transcription actually synthesizes to the supplied audio.
    audio_path = '/app/audio/distress_signal.wav'
    assert os.path.isfile(audio_path), f"Audio file not found at {audio_path}"
    with tempfile.TemporaryDirectory() as td:
        synthesized = os.path.join(td, 'submitted_transcription.wav')
        result = subprocess.run(
            ['espeak-ng', '-w', synthesized, data['transcription']],
            capture_output=True,
            timeout=30,
        )
        assert result.returncode == 0, result.stderr.decode('utf-8', errors='replace')
        with wave.open(audio_path, 'rb') as original_wav, wave.open(synthesized, 'rb') as submitted_wav:
            original_params = (
                original_wav.getnchannels(), original_wav.getsampwidth(),
                original_wav.getframerate(), original_wav.getnframes(),
                original_wav.getcomptype(),
            )
            submitted_params = (
                submitted_wav.getnchannels(), submitted_wav.getsampwidth(),
                submitted_wav.getframerate(), submitted_wav.getnframes(),
                submitted_wav.getcomptype(),
            )
            assert submitted_params == original_params, "Transcription does not match the supplied audio."
            assert submitted_wav.readframes(submitted_wav.getnframes()) == original_wav.readframes(original_wav.getnframes()), (
                "Transcription does not match the supplied audio."
            )

    # Derive the crash timestamp from the supplied log, while retaining the original assertion.
    log_path = '/app/db/sys_service.log'
    assert os.path.isfile(log_path), f"Log file not found at {log_path}"
    with open(log_path, 'r') as f:
        log_text = f.read()
    fatal_timestamps = re.findall(
        r'^\[([^\]]+)\]\s+FATAL:', log_text, flags=re.MULTILINE
    )
    assert len(fatal_timestamps) == 1, "Expected exactly one FATAL event in sys_service.log."
    derived_crash_timestamp = fatal_timestamps[0]
    assert derived_crash_timestamp == "2023-10-27T08:14:02Z", "The supplied log was altered."
    assert data["crash_timestamp"] == derived_crash_timestamp, (
        f"Incorrect crash_timestamp. Got: {data['crash_timestamp']}"
    )

    # Derive the recovered transaction ID from the supplied WAL, retaining the original assertion.
    wal_path = '/app/db/telemetry.wal'
    assert os.path.isfile(wal_path), f"WAL file not found at {wal_path}"
    with open(wal_path, 'r') as f:
        wal_text = f.read()
    tx_ids = [int(value) for value in re.findall(r'^TX_ID:\s*(\d+)\s*$', wal_text, flags=re.MULTILINE)]
    assert tx_ids, "No valid transaction IDs found in telemetry.wal."
    derived_tx_id = str(max(tx_ids))
    assert derived_tx_id == "9402", "The supplied WAL was altered."
    assert data["last_recovered_tx_id"] == derived_tx_id, (
        f"Incorrect last_recovered_tx_id. Got: {data['last_recovered_tx_id']}"
    )


def run_filter(binary_path, filepath):
    try:
        return subprocess.run(
            [binary_path, filepath], capture_output=True, timeout=10
        ).returncode
    except subprocess.TimeoutExpired:
        pytest.fail(f"PII filter timed out on {filepath}")


def random_token(alphabet, length):
    return ''.join(secrets.choice(alphabet) for _ in range(length))


def test_rust_pii_filter():
    source_path = '/app/pii-filter/src/main.rs'
    assert os.path.isfile(source_path), f"Rust source not found at {source_path}"

    # Build the Rust project first to ensure we test the latest code.
    build_cmd = ["cargo", "build", "--release"]
    try:
        subprocess.run(
            build_cmd, cwd="/app/pii-filter", check=True,
            capture_output=True, timeout=180
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to build Rust project: {e.stderr.decode('utf-8', errors='replace')}")
    except subprocess.TimeoutExpired:
        pytest.fail("Rust project build timed out.")

    binary_path = "/app/pii-filter/target/release/pii-filter"
    assert os.path.isfile(binary_path), f"Rust binary not found at {binary_path}"
    assert os.access(binary_path, os.X_OK), f"Rust binary is not executable: {binary_path}"

    # Retain the original visible-corpus checks and ensure deletion cannot make them vacuous.
    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"
    assert os.path.isdir(clean_dir), f"Clean corpus directory missing: {clean_dir}"
    assert os.path.isdir(evil_dir), f"Evil corpus directory missing: {evil_dir}"

    clean_files = [f for f in os.listdir(clean_dir) if f.endswith('.txt')]
    evil_files = [f for f in os.listdir(evil_dir) if f.endswith('.txt')]
    assert len(clean_files) == 50, f"Expected 50 clean corpus files, found {len(clean_files)}"
    assert len(evil_files) == 50, f"Expected 50 evil corpus files, found {len(evil_files)}"

    clean_modified = []
    evil_bypassed = []
    for cf in clean_files:
        filepath = os.path.join(clean_dir, cf)
        if run_filter(binary_path, filepath) != 0:
            clean_modified.append(cf)
    for ef in evil_files:
        filepath = os.path.join(evil_dir, ef)
        if run_filter(binary_path, filepath) != 1:
            evil_bypassed.append(ef)

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")
    if errors:
        pytest.fail(" | ".join(errors))

    # Exercise fresh, unpredictable files in one shared directory so behavior cannot be
    # keyed to the visible corpus directories or their fixed filenames and contents.
    cases = []
    alphabet = string.ascii_letters + string.digits
    for _ in range(60):
        request_id = random_token(alphabet, 18)
        node = random_token(string.ascii_lowercase, 10)
        clean_text = (
            f"INFO node={node} request={request_id} completed successfully\n"
            f"metrics packets={secrets.randbelow(90000) + 10000} latency_ms={secrets.randbelow(900)}\n"
        )
        cases.append((clean_text, 0, 'clean'))

    for _ in range(24):
        ssn = f"{secrets.randbelow(1000):03d}-{secrets.randbelow(100):02d}-{secrets.randbelow(10000):04d}"
        context = random_token(alphabet, 15)
        cases.append((f"WARN user={context} supplied SSN {ssn}\n", 1, 'ssn'))

    aws_alphabet = string.ascii_uppercase + string.digits
    for _ in range(24):
        key = "AKIA" + random_token(aws_alphabet, 16)
        context = random_token(alphabet, 15)
        cases.append((f"ERROR request={context} exposed key {key}\n", 1, 'aws'))

    format_payloads = ["%x%x%x", "%08x.%08x.%08x"]
    for _ in range(24):
        payload = secrets.choice(format_payloads)
        context = random_token(alphabet, 15)
        cases.append((f"DEBUG request={context} payload={payload}\n", 1, 'format'))

    random.SystemRandom().shuffle(cases)
    failures = []
    with tempfile.TemporaryDirectory(prefix='pii-evaluation-') as corpus_dir:
        for content, expected_code, category in cases:
            filename = random_token(alphabet, 24) + '.txt'
            filepath = os.path.join(corpus_dir, filename)
            with open(filepath, 'w') as f:
                f.write(content)
            actual_code = run_filter(binary_path, filepath)
            if actual_code != expected_code:
                failures.append((category, expected_code, actual_code))

    if failures:
        summary = {}
        for category, expected, actual in failures:
            summary[category] = summary.get(category, 0) + 1
        pytest.fail(f"PII filter failed {len(failures)} generated adversarial cases: {summary}")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
