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
import csv
import hashlib
import json
import os
import xml.etree.ElementTree as ET

import pytest
import requests

AUDIO_SOURCE = "/app/research_data/interview_sample.wav"
AUDIO_DEST = "/home/user/organized_data/interview_sample.wav"
MANIFEST_PATH = "/home/user/organized_data/manifest.json"
CSV_PATH = "/app/research_data/index.csv"
XML_PATH = "/app/research_data/metadata.xml"
API_URL = "http://127.0.0.1:9090/api/v1/record"
AUTH_HEADER = {"Authorization": "Bearer delta-v-2024"}
EXPECTED_TRANSCRIPT = "the patient exhibits mild symptoms"


def get_sha256(path):
    sha256_hash = hashlib.sha256()
    with open(path, "rb") as f:
        for byte_block in iter(lambda: f.read(4096), b""):
            sha256_hash.update(byte_block)
    return sha256_hash.hexdigest()


def source_metadata():
    with open(CSV_PATH, newline="", encoding="utf-8") as f:
        row = next(
            (row for row in csv.DictReader(f)
             if row.get("filename") == "interview_sample.wav"),
            None,
        )
    assert row is not None, "Source CSV has no interview_sample.wav row"

    location = None
    for record in ET.parse(XML_PATH).getroot().findall("record"):
        if record.findtext("file") == "interview_sample.wav":
            location = record.findtext("location")
            break
    assert location is not None, "Source XML has no interview_sample.wav record"
    return row["participant_id"], location


def manifest_item():
    assert os.path.isfile(MANIFEST_PATH), f"Manifest file missing at {MANIFEST_PATH}"
    with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Manifest is not valid JSON")

    assert isinstance(data, list), "Manifest must be a JSON array"
    item = next(
        (x for x in data if isinstance(x, dict) and
         x.get("filename") == "interview_sample.wav"),
        None,
    )
    assert item is not None, "Manifest missing entry for interview_sample.wav"
    return item


def test_audio_copied():
    assert os.path.isfile(AUDIO_SOURCE), f"Source audio missing at {AUDIO_SOURCE}"
    assert os.path.isfile(AUDIO_DEST), f"Audio file not copied to {AUDIO_DEST}"
    assert get_sha256(AUDIO_DEST) == get_sha256(AUDIO_SOURCE), \
        "Organized audio is not an exact copy of the source audio"


def test_manifest_exists_and_valid():
    item = manifest_item()

    expected_keys = {"filename", "checksum", "participant_id", "location", "transcript"}
    assert set(item.keys()) == expected_keys, \
        f"Manifest entry keys mismatch. Expected {expected_keys}, got {set(item.keys())}"

    expected_participant, expected_location = source_metadata()
    assert item["participant_id"] == expected_participant, \
        "participant_id does not match the source CSV"
    assert item["location"] == expected_location, \
        "location does not match the source XML"

    # Preserve the original source-data assertions as well.
    assert item["participant_id"] == "P-8842", \
        f"Expected participant_id P-8842, got {item['participant_id']}"
    assert item["location"] == "Clinic B", \
        f"Expected location Clinic B, got {item['location']}"

    actual_checksum = get_sha256(AUDIO_DEST)
    source_checksum = get_sha256(AUDIO_SOURCE)
    assert actual_checksum == source_checksum, \
        "Organized audio checksum does not match source audio"
    assert item["checksum"] == actual_checksum, \
        f"Checksum in manifest ({item['checksum']}) does not match actual file checksum ({actual_checksum})"

    transcript = item["transcript"]
    assert isinstance(transcript, str), "Transcript must be text"
    assert transcript == EXPECTED_TRANSCRIPT, \
        f"Transcript must exactly match the spoken audio; got: {transcript!r}"
    assert transcript == transcript.lower(), "Transcript must be lowercase"
    assert all(c.islower() or c.isdigit() or c.isspace() for c in transcript), \
        "Transcript must not contain punctuation"
    for word in ["patient", "exhibits", "mild", "symptoms"]:
        assert word in transcript.lower(), \
            f"Transcript missing expected word: '{word}'. Actual transcript: {transcript.lower()}"


def test_api_unauthorized():
    for headers in ({}, {"Authorization": "Bearer incorrect-token"}):
        try:
            response = requests.get(
                f"{API_URL}?file=interview_sample.wav",
                headers=headers,
                timeout=5,
            )
        except requests.RequestException as e:
            pytest.fail(f"Failed to connect to API: {e}")

        assert response.status_code == 401, \
            f"Expected HTTP 401 Unauthorized without valid auth header, got {response.status_code}"


def test_api_authorized():
    try:
        response = requests.get(
            f"{API_URL}?file=interview_sample.wav",
            headers=AUTH_HEADER,
            timeout=5,
        )
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to API: {e}")

    assert response.status_code == 200, \
        f"Expected HTTP 200 OK with auth header, got {response.status_code}"
    content_type = response.headers.get("Content-Type", "")
    assert content_type.split(";", 1)[0].strip().lower() == "application/json", \
        f"Expected Content-Type application/json, got {content_type!r}"

    try:
        data = response.json()
    except (json.JSONDecodeError, requests.exceptions.JSONDecodeError):
        pytest.fail("API response is not valid JSON")

    item = manifest_item()
    assert data == item, "API response must equal the exact manifest object"

    assert data.get("filename") == "interview_sample.wav", \
        "API response filename mismatch"
    assert data.get("participant_id") == "P-8842", \
        "API response participant_id mismatch"
    assert data.get("location") == "Clinic B", \
        "API response location mismatch"

    actual_checksum = get_sha256(AUDIO_DEST)
    assert data.get("checksum") == actual_checksum, \
        "API response checksum does not match actual file checksum"

    transcript = data.get("transcript", "").lower()
    for word in ["patient", "exhibits", "mild", "symptoms"]:
        assert word in transcript, \
            f"API Transcript missing expected word: '{word}'. Actual: {transcript}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
