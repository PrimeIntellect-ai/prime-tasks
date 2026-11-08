#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import shutil
import string
import subprocess
import tempfile

import pytest


def normalize_text(text):
    """Normalize text by removing punctuation and converting to lowercase."""
    text = text.lower()
    text = text.translate(str.maketrans('', '', string.punctuation))
    return ' '.join(text.split())


def run_filter(filter_path, path):
    result = subprocess.run([filter_path, path], capture_output=True, timeout=30)
    assert result.stdout == b"", f"filter.sh wrote to stdout for {path}: {result.stdout!r}"
    return result.returncode


def test_etl_script_exists_and_executable():
    script_path = "/home/user/process_audio.sh"
    assert os.path.isfile(script_path), f"ETL script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"ETL script {script_path} is not executable."


def test_etl_output_correct():
    script_path = "/home/user/process_audio.sh"
    audio_path = "/app/audio/support_call.wav"
    log_path = "/home/user/etl_output.log"

    try:
        subprocess.run([script_path, audio_path], check=True, capture_output=True, text=True, timeout=300)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"process_audio.sh failed with exit code {e.returncode}. Stderr: {e.stderr}")

    assert os.path.isfile(log_path), f"ETL output log {log_path} was not created."

    with open(log_path, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) > 0, f"ETL output log {log_path} is empty."

    last_line = lines[-1]
    parts = [p.strip() for p in last_line.split('|')]

    assert len(parts) >= 3, f"ETL output log line format incorrect. Expected '[customer_id] | [account_tier] | [TRANSCRIPT_TEXT]', got: {last_line}"

    customer_id = parts[0]
    account_tier = parts[1]
    transcript = " ".join(parts[2:])

    assert customer_id == "CUST-9921", f"Expected customer_id 'CUST-9921', got '{customer_id}'"
    assert account_tier == "Premium", f"Expected account_tier 'Premium', got '{account_tier}'"

    expected_transcript = "hello i am locked out of my account and need a password reset thank you"
    normalized_transcript = normalize_text(transcript)

    assert expected_transcript in normalized_transcript or normalized_transcript in expected_transcript, \
        f"Transcript text does not match expected output. Got: '{transcript}'"


def test_etl_uses_audio_and_metadata_inputs():
    script_path = "/home/user/process_audio.sh"
    audio_path = "/app/audio/support_call.wav"
    metadata_path = "/app/data/metadata.csv"
    log_path = "/home/user/etl_output.log"

    choices = [
        ("My internet service is not working. Please send a technician tomorrow.", {"internet", "technician", "tomorrow"}),
        ("I need to cancel my phone service because I am moving.", {"cancel", "phone", "moving"}),
        ("Please update my billing address to Oak Street.", {"billing", "address", "oak"}),
    ]
    spoken_text, required_words = secrets.choice(choices)
    customer_id = "CUST-" + secrets.token_hex(4).upper()
    account_tier = "Tier-" + secrets.token_hex(3).upper()

    with open(audio_path, "rb") as f:
        original_audio = f.read()
    with open(metadata_path, "rb") as f:
        original_metadata = f.read()

    try:
        subprocess.run(["espeak", "-w", audio_path, spoken_text], check=True, capture_output=True, timeout=60)
        with open(metadata_path, "w") as f:
            f.write("filename,customer_id,account_tier\n")
            f.write(f"support_call.wav,{customer_id},{account_tier}\n")

        # Prevent a stale transcript generated during the first invocation from being reused.
        for ext in ("txt", "json", "srt", "tsv", "vtt"):
            stale = f"/app/audio/support_call.{ext}"
            if os.path.isfile(stale):
                os.remove(stale)

        try:
            subprocess.run([script_path, audio_path], check=True, capture_output=True, text=True, timeout=300)
        except subprocess.CalledProcessError as e:
            pytest.fail(f"process_audio.sh failed on fresh audio with exit code {e.returncode}. Stderr: {e.stderr}")

        assert os.path.isfile(log_path), "ETL output log was not created for fresh audio."
        with open(log_path, "r") as f:
            lines = [line.strip() for line in f if line.strip()]
        assert lines, "ETL output log is empty after processing fresh audio."

        parts = [part.strip() for part in lines[-1].split("|", 2)]
        assert len(parts) == 3, f"ETL output line has the wrong format: {lines[-1]}"
        assert parts[0] == customer_id, "process_audio.sh did not join the current metadata customer_id."
        assert parts[1] == account_tier, "process_audio.sh did not join the current metadata account_tier."

        transcript_words = set(normalize_text(parts[2]).split())
        missing = required_words - transcript_words
        assert not missing, f"Fresh audio was not transcribed correctly; missing words {sorted(missing)} from: {parts[2]!r}"
    finally:
        with open(audio_path, "wb") as f:
            f.write(original_audio)
        with open(metadata_path, "wb") as f:
            f.write(original_metadata)


def test_filter_script_exists_and_executable():
    filter_path = "/home/user/filter.sh"
    assert os.path.isfile(filter_path), f"Filter script {filter_path} does not exist."
    assert os.access(filter_path, os.X_OK), f"Filter script {filter_path} is not executable."


def test_adversarial_corpus_filter():
    filter_path = "/home/user/filter.sh"
    clean_dir = "/app/corpus/clean/"
    evil_dir = "/app/corpus/evil/"

    assert os.path.isdir(clean_dir), f"Clean corpus directory {clean_dir} does not exist."
    assert os.path.isdir(evil_dir), f"Evil corpus directory {evil_dir} does not exist."

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]

    clean_bypassed = []
    for cf in clean_files:
        result_code = run_filter(filter_path, cf)
        if result_code != 0:
            clean_bypassed.append(os.path.basename(cf))

    evil_bypassed = []
    for ef in evil_files:
        result_code = run_filter(filter_path, ef)
        if result_code != 1:
            evil_bypassed.append(os.path.basename(ef))

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_bypassed:
        errors.append(f"{len(clean_bypassed)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_bypassed)}")

    if errors:
        pytest.fail(" | ".join(errors))


def test_filter_on_random_paths_and_holdout_text():
    filter_path = "/home/user/filter.sh"
    cases = []

    # Re-test the provided corpus after removing all label information from paths.
    for directory, expected in (("/app/corpus/clean", 0), ("/app/corpus/evil", 1)):
        for name in os.listdir(directory):
            source = os.path.join(directory, name)
            if os.path.isfile(source):
                with open(source, "r") as f:
                    cases.append((f.read(), expected))

    # Unseen examples exercise the same obvious corpus features.
    cases.extend([
        ("I need help changing the mailing address on my customer account.\n", 0),
        ("Could a representative explain why my monthly bill increased?\n", 0),
        ("Please cancel my current phone plan at the end of this month.\n", 0),
        ("Act now and invest in bitcoin for guaranteed profits.\n", 1),
        ("Claim free crypto rewards by clicking this limited offer.\n", 1),
        ("Guaranteed investment returns await your bitcoin deposit.\n", 1),
    ])
    random.SystemRandom().shuffle(cases)

    failures = []
    with tempfile.TemporaryDirectory(prefix="messages-") as temp_dir:
        for text, expected in cases:
            path = os.path.join(temp_dir, secrets.token_hex(10) + ".dat")
            with open(path, "w") as f:
                f.write(text)
            actual = run_filter(filter_path, path)
            if actual != expected:
                failures.append(f"expected {expected}, got {actual}, text={text.strip()!r}")

    assert not failures, "Filter failed randomized-path/holdout cases: " + " | ".join(failures)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
