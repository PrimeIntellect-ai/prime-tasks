#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import subprocess
import time
import uuid

import pytest
import requests

API_URL = "http://127.0.0.1:8000/inventory"
DROPZONE_DIR = "/home/user/dataset/dropzone"
ORGANIZED_DIR = "/home/user/dataset/organized"
TEST_FOLDER_DIR = os.path.join(DROPZONE_DIR, "test_folder")
ORIGINAL_AUDIO = "/app/audio_sample.wav"
DROPPED_AUDIO_1 = os.path.join(TEST_FOLDER_DIR, "audio_sample.wav")
DROPPED_AUDIO_2 = os.path.join(DROPZONE_DIR, "second.wav")

_model = None


def whisper_category(path):
    global _model
    try:
        import whisper
    except ImportError as exc:
        pytest.fail(f"The required Whisper package is not installed: {exc}")

    if _model is None:
        try:
            _model = whisper.load_model("tiny")
        except Exception as exc:
            pytest.fail(f"Could not load the required Whisper tiny model: {exc}")

    try:
        result = _model.transcribe(path, fp16=False)
    except Exception as exc:
        pytest.fail(f"Whisper failed to transcribe {path}: {exc}")

    assert isinstance(result, dict) and isinstance(result.get("text"), str), \
        "Whisper did not return a textual transcription"
    return result["text"].strip().lower()


def get_inventory():
    try:
        response = requests.get(API_URL, timeout=5)
    except requests.RequestException as exc:
        pytest.fail(f"Failed to connect to {API_URL}: {exc}")

    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail("API response is not valid JSON")
    assert isinstance(data, dict), "The /inventory response must be a JSON object"
    return data


def test_api_and_first_file_processing():
    # Ensure the first file was dropped where expected.
    assert os.path.exists(DROPPED_AUDIO_1), f"File {DROPPED_AUDIO_1} is missing. Did you copy it?"

    expected_category = whisper_category(ORIGINAL_AUDIO)
    data = get_inventory()

    # Find the category (transcription) for audio_sample.wav.
    category = None
    expected_organized_path = None
    expected_path_suffix = "audio_sample.wav"
    for cat, paths in data.items():
        for p in paths:
            if p.endswith(expected_path_suffix):
                category = cat
                expected_organized_path = p
                break
        if category is not None:
            break

    assert category is not None, "Could not find audio_sample.wav in the /inventory response"
    assert category == expected_category, \
        f"Expected Whisper category {expected_category!r}, got {category!r}"

    # Verify the path matches the expected pattern.
    expected_path = os.path.join(ORGANIZED_DIR, category, "audio_sample.wav")
    assert expected_organized_path == expected_path, \
        f"Expected path {expected_path}, got {expected_organized_path}"

    # Verify the organized file exists.
    assert os.path.exists(expected_path), f"Organized file {expected_path} does not exist"

    # Verify it is a hard link.
    stat_drop = os.stat(DROPPED_AUDIO_1)
    stat_org = os.stat(expected_path)
    assert stat_drop.st_ino == stat_org.st_ino, \
        f"File {expected_path} is not a hard link to {DROPPED_AUDIO_1}"


def test_watchdog_processes_new_file():
    expected_category = whisper_category(ORIGINAL_AUDIO)

    # Drop a new file.
    shutil.copy(ORIGINAL_AUDIO, DROPPED_AUDIO_2)

    # Wait for the watchdog to process it.
    max_retries = 15
    found = False
    category = None

    for _ in range(max_retries):
        time.sleep(1)
        try:
            response = requests.get(API_URL, timeout=5)
            if response.status_code == 200:
                data = response.json()
                for cat, paths in data.items():
                    for p in paths:
                        if p.endswith("second.wav"):
                            found = True
                            category = cat
                            break
                    if found:
                        break
            if found:
                break
        except requests.RequestException:
            pass

    assert found, "Watchdog did not process the newly dropped file 'second.wav' within the timeout"
    assert category == expected_category, \
        f"Expected Whisper category {expected_category!r}, got {category!r}"

    expected_path = os.path.join(ORGANIZED_DIR, category, "second.wav")
    assert os.path.exists(expected_path), f"Organized file {expected_path} does not exist"

    stat_drop = os.stat(DROPPED_AUDIO_2)
    stat_org = os.stat(expected_path)
    assert stat_drop.st_ino == stat_org.st_ino, \
        f"File {expected_path} is not a hard link to {DROPPED_AUDIO_2}"


def test_distinct_audio_is_transcribed_and_processed_recursively():
    # Use fresh, distinct speech so a service that assigns one constant category
    # to every WAV cannot pass. The expected answer is independently derived by
    # running the required Whisper tiny model.
    adjectives = ["silver", "gentle", "bright", "quiet", "golden"]
    animals = ["rabbit", "tiger", "panda", "falcon", "otter"]
    places = ["garden", "station", "harbor", "library", "market"]
    phrase = f"the {secrets.choice(adjectives)} {secrets.choice(animals)} visits the {secrets.choice(places)}"

    token = uuid.uuid4().hex
    source_audio = f"/tmp/generated-{token}.wav"
    filename = f"fresh-{token}.wav"
    nested_dir = os.path.join(DROPZONE_DIR, f"nested-{token}", "deeper")
    dropped_audio = os.path.join(nested_dir, filename)

    subprocess.run(["espeak", "-w", source_audio, phrase], check=True)
    expected_category = whisper_category(source_audio)
    assert expected_category != whisper_category(ORIGINAL_AUDIO), \
        "The distinct verification audio unexpectedly produced the sample category"

    os.makedirs(nested_dir, exist_ok=True)
    shutil.copy(source_audio, dropped_audio)

    expected_path = os.path.join(ORGANIZED_DIR, expected_category, filename)
    found = False
    for _ in range(45):
        time.sleep(1)
        try:
            data = get_inventory()
        except pytest.fail.Exception:
            continue
        paths = data.get(expected_category, [])
        if expected_path in paths:
            found = True
            break

    assert found, \
        f"Watchdog did not report {filename} under Whisper category {expected_category!r}"
    assert os.path.exists(expected_path), f"Organized file {expected_path} does not exist"

    stat_drop = os.stat(dropped_audio)
    stat_org = os.stat(expected_path)
    assert stat_drop.st_ino == stat_org.st_ino, \
        f"File {expected_path} is not a hard link to {dropped_audio}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
