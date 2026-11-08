#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import secrets
import shutil
import subprocess
import tarfile
import tempfile

import pytest

SCRIPT_PATH = "/home/user/curate_audio.sh"
EVIL_DIR = "/app/audio_eval/evil"
CLEAN_DIR = "/app/audio_eval/clean"


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable"


def test_curation_pipeline():
    work_dir = tempfile.mkdtemp(prefix="audio_curation_")
    combined_dir = os.path.join(work_dir, "input")
    output_tar = os.path.join(work_dir, "output.tar.gz")
    extract_dir = os.path.join(work_dir, "extracted")
    os.makedirs(combined_dir)

    evil_sources = {}
    clean_sources = {}

    # Retain the original fixture checks.
    for filename in os.listdir(EVIL_DIR):
        if filename.endswith(".wav"):
            destination = os.path.join(combined_dir, filename)
            shutil.copy(os.path.join(EVIL_DIR, filename), destination)
            evil_sources[filename] = destination

    for filename in os.listdir(CLEAN_DIR):
        if filename.endswith(".wav"):
            destination = os.path.join(combined_dir, filename)
            shutil.copy(os.path.join(CLEAN_DIR, filename), destination)
            clean_sources[filename] = destination

    # Create additional test audio only after the agent has finished. Names are
    # random and carry no label, and generation order is independently shuffled.
    code_words = ["cedar", "harbor", "meadow", "silver", "orbit", "willow"]
    prefixes = [
        "Please review the following voice memo.",
        "This is an update for the project team.",
        "The recording contains today's status message.",
    ]
    suffixes = [
        "The meeting will continue tomorrow.",
        "Please file the report after review.",
        "The next update is scheduled for Monday.",
    ]
    specs = [
        (True, "This material is confidential and must be withheld."),
        (True, "Access to this recording is restricted to authorized staff."),
        (False, "This material is approved for ordinary circulation."),
        (False, "Access to this recording is available to the project staff."),
    ]
    rng = secrets.SystemRandom()
    rng.shuffle(specs)

    for is_evil, core in specs:
        filename = f"recording_{secrets.token_hex(12)}.wav"
        phrase = f"{rng.choice(prefixes)} Project {rng.choice(code_words)}. {core} {rng.choice(suffixes)}"
        destination = os.path.join(combined_dir, filename)
        generated = subprocess.run(
            ["espeak", "-w", destination, phrase],
            capture_output=True,
            text=True,
        )
        assert generated.returncode == 0, (
            f"Failed to generate hidden WAV: {generated.stderr}"
        )
        if is_evil:
            evil_sources[filename] = destination
        else:
            clean_sources[filename] = destination

    result = subprocess.run(
        [SCRIPT_PATH, combined_dir, output_tar],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, (
        f"Script failed with return code {result.returncode}\n"
        f"STDOUT: {result.stdout}\nSTDERR: {result.stderr}"
    )
    assert os.path.exists(output_tar), f"Output archive {output_tar} was not created"

    os.makedirs(extract_dir)
    with tarfile.open(output_tar, "r:gz") as tar:
        tar.extractall(path=extract_dir)

    manifest_path = os.path.join(extract_dir, "manifest.json")
    assert os.path.exists(manifest_path), "manifest.json not found in the archive"

    with open(manifest_path, "r") as manifest_file:
        try:
            manifest = json.load(manifest_file)
        except json.JSONDecodeError:
            pytest.fail("manifest.json is not valid JSON")

    assert "files" in manifest, "manifest.json does not contain 'files' key"
    manifest_files = {
        item.get("filename"): item for item in manifest.get("files", [])
    }

    evil_bypassed = []
    for filename in evil_sources:
        if filename in manifest_files or os.path.exists(
            os.path.join(extract_dir, filename)
        ):
            evil_bypassed.append(filename)

    clean_modified = []
    for filename, original_path in clean_sources.items():
        extracted_path = os.path.join(extract_dir, filename)
        if filename not in manifest_files or not os.path.exists(extracted_path):
            clean_modified.append(filename)
            continue

        original_size = os.path.getsize(original_path)
        with open(original_path, "rb") as original_file:
            original_sha256 = hashlib.sha256(original_file.read()).hexdigest()

        manifest_item = manifest_files[filename]
        if manifest_item.get("size") != original_size:
            clean_modified.append(f"{filename} (wrong size)")
        if manifest_item.get("sha256") != original_sha256:
            clean_modified.append(f"{filename} (wrong sha256)")

    error_msg = []
    if evil_bypassed:
        error_msg.append(
            f"{len(evil_bypassed)} of {len(evil_sources)} evil bypassed: "
            + ", ".join(evil_bypassed)
        )
    if clean_modified:
        error_msg.append(
            f"{len(clean_modified)} of {len(clean_sources)} clean modified/missing: "
            + ", ".join(clean_modified)
        )

    if error_msg:
        pytest.fail(" | ".join(error_msg))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
