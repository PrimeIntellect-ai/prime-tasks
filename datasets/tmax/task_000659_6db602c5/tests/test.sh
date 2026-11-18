#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import subprocess
import sys
import uuid
import zipfile


def test_audio_transcription():
    transcript_path = "/home/user/audio_transcript.txt"
    assert os.path.isfile(transcript_path), f"Missing transcript file: {transcript_path}"

    with open(transcript_path, "r") as f:
        content = f.read().lower()

    content = re.sub(r"[^\w\s]", "", content)
    expected = "Subject confirmed the anomaly originates from sector 7G".lower()
    expected = re.sub(r"[^\w\s]", "", expected)
    assert expected in content, f"Transcript does not contain the expected text. Expected: {expected}"


def test_adversarial_corpus_processing():
    input_dir = "/app/corpora/incoming"
    output_dir = "/home/user/extracted_datasets"
    rejected_log = "/home/user/rejected_archives.log"

    assert os.path.isfile(rejected_log), f"Missing rejected archives log: {rejected_log}"
    with open(rejected_log, "r") as f:
        rejected_files = [line.strip() for line in f.readlines() if line.strip()]

    evil_zips = ["evil_1.zip"]
    clean_zips = ["clean_1.zip"]
    for name in evil_zips + clean_zips:
        assert os.path.isfile(os.path.join(input_dir, name)), f"Missing corpus archive: {name}"

    evil_bypassed = []
    for evil in evil_zips:
        if evil not in rejected_files:
            evil_bypassed.append(evil)
        basename = evil[:-4]
        if os.path.exists(os.path.join(output_dir, basename)):
            evil_bypassed.append(evil + " (extracted)")
    assert not evil_bypassed, f"{len(evil_bypassed)} of {len(evil_zips)} evil bypassed: {evil_bypassed}"

    clean_modified = []
    for clean in clean_zips:
        if clean in rejected_files:
            clean_modified.append(clean + " (rejected)")
            continue
        basename = clean[:-4]
        extracted_path = os.path.join(output_dir, basename)
        if not os.path.isdir(extracted_path):
            clean_modified.append(clean + " (not extracted)")
            continue
        json_path = os.path.join(extracted_path, "events.json")
        if not os.path.isfile(json_path):
            clean_modified.append(clean + " (missing events.json)")
            continue
        try:
            with open(json_path, "r") as f:
                data = json.load(f)
            if not isinstance(data, list):
                clean_modified.append(clean + " (events.json is not a list)")
        except json.JSONDecodeError:
            clean_modified.append(clean + " (invalid JSON)")
    assert not clean_modified, f"{len(clean_modified)} of {len(clean_zips)} clean modified/failed: {clean_modified}"


def test_processor_executes_securely_and_parses(tmp_path):
    processor = "/home/user/dataset_processor.py"
    assert os.path.isfile(processor), f"Missing processor script: {processor}"

    input_dir = tmp_path / "incoming"
    output_dir = tmp_path / "output"
    input_dir.mkdir()
    token = uuid.uuid4().hex
    clean_name = f"clean_{token}.zip"
    evil_name = f"evil_{token}.zip"
    entry_one = f"event-{token}-one"
    entry_two = f"event-{token}-two"
    log_text = f"{entry_one}\ndetail one\n---\n{entry_two}\ndetail two\n"

    with zipfile.ZipFile(input_dir / clean_name, "w") as archive:
        archive.writestr("events.log", log_text)

    escaped_path = tmp_path / f"escaped_{token}.txt"
    absolute_path = f"/tmp/absolute_{token}.txt"
    with zipfile.ZipFile(input_dir / evil_name, "w") as archive:
        archive.writestr(f"../../escaped_{token}.txt", "compromised")
        archive.writestr(absolute_path, "compromised")
        archive.writestr("events.log", "must not be extracted")

    result = subprocess.run(
        [sys.executable, processor, str(input_dir), str(output_dir)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"Processor failed:\nstdout: {result.stdout}\nstderr: {result.stderr}"

    rejected_log = "/home/user/rejected_archives.log"
    assert os.path.isfile(rejected_log), f"Missing rejected archives log: {rejected_log}"
    with open(rejected_log, "r") as f:
        rejected = [line.strip() for line in f if line.strip()]
    assert evil_name in rejected, "Dynamically generated malicious archive was not rejected"
    assert clean_name not in rejected, "Dynamically generated clean archive was rejected"
    assert not (output_dir / evil_name[:-4]).exists(), "Malicious archive was partially extracted"
    assert not escaped_path.exists(), "Relative Zip Slip payload escaped the extraction directory"
    assert not os.path.exists(absolute_path), "Absolute-path ZIP payload was written"

    clean_output = output_dir / clean_name[:-4]
    assert clean_output.is_dir(), "Clean archive was not extracted"
    assert (clean_output / "events.log").read_text() == log_text
    json_path = clean_output / "events.json"
    assert json_path.is_file(), "Clean archive is missing events.json"
    with open(json_path, "r") as f:
        parsed = json.load(f)
    assert isinstance(parsed, list), "events.json is not a list"
    assert len(parsed) == 2, "events.json must contain one object per multi-line log entry"
    assert all(isinstance(item, dict) for item in parsed), "Each parsed log entry must be an object"
    assert entry_one in json.dumps(parsed[0]), "First parsed entry does not contain its event data"
    assert entry_two in json.dumps(parsed[1]), "Second parsed entry does not contain its event data"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
