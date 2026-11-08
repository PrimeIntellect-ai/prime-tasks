#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import array
import hashlib
import json
import os
import re
import secrets
import subprocess
import time
import wave
import zipfile

import pytest
import requests

API_URL = "http://127.0.0.1:8000/api/dataset"
INCOMING_DIR = "/home/user/incoming_archives"
PROCESSED_DIR = "/home/user/processed_audio"
SOURCE_AUDIO = "/app/field_note.wav"
FILENAME_RE = re.compile(r"^field_record_[a-f0-9]{32}\.wav$")


def get_dataset(timeout=5):
    try:
        response = requests.get(API_URL, timeout=timeout)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the HTTP API at {API_URL}. Is the service running? Error: {exc}")
    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response from {API_URL} is not valid JSON. Response text: {response.text}")
    assert isinstance(data, dict), f"Expected JSON response to be a dictionary, got {type(data)}"
    return data


def decoded_pcm(path):
    result = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-ac", "1", "-ar", "16000", "-f", "s16le", "-acodec", "pcm_s16le", "-"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    assert result.returncode == 0, f"ffmpeg could not decode {path}: {result.stderr.decode(errors='replace')}"
    samples = array.array("h")
    samples.frombytes(result.stdout)
    return samples


def audio_matches_source(candidate, reference):
    samples = decoded_pcm(candidate)
    if abs(len(samples) - len(reference)) > 1600:
        return False
    count = min(len(samples), len(reference))
    if count == 0:
        return False
    mean_absolute_error = sum(abs(int(samples[i]) - int(reference[i])) for i in range(count)) / count
    return mean_absolute_error <= 300


def validate_dataset_and_files(data):
    assert len(data) > 0, "The dataset API returned an empty dictionary, expected at least one entry."
    found_target_transcript = False

    for filename, transcript in data.items():
        assert FILENAME_RE.match(filename), f"Filename '{filename}' does not match the required format 'field_record_<md5>.wav'"
        assert isinstance(transcript, str), f"Expected transcript for '{filename}' to be a string, got {type(transcript)}"

        transcript_lower = transcript.lower()
        if "blue-winged warbler" in transcript_lower and "northern creek" in transcript_lower:
            found_target_transcript = True

        filepath = os.path.join(PROCESSED_DIR, filename)
        assert os.path.isfile(filepath), f"Audio file {filepath} referenced in API response does not exist."

        with open(filepath, "rb") as audio_file:
            actual_md5 = hashlib.md5(audio_file.read()).hexdigest()
        expected_filename = f"field_record_{actual_md5}.wav"
        assert filename == expected_filename, f"Filename '{filename}' does not match its actual MD5 hash. Expected '{expected_filename}'."

        try:
            with wave.open(filepath, "rb") as wav_file:
                channels = wav_file.getnchannels()
                framerate = wav_file.getframerate()
                assert channels == 1, f"Audio file {filename} is not mono (channels={channels})."
                assert framerate == 16000, f"Audio file {filename} does not have a 16kHz sample rate (framerate={framerate})."
        except wave.Error as exc:
            pytest.fail(f"Failed to read {filepath} as a WAV file: {exc}")

    assert found_target_transcript, "None of the transcripts contained the expected phrases ('blue-winged warbler' and 'northern creek')."


def test_archive_watcher_audio_processing_and_api():
    assert os.path.isdir(INCOMING_DIR), f"Directory {INCOMING_DIR} does not exist."
    assert os.path.isdir(PROCESSED_DIR), f"Directory {PROCESSED_DIR} does not exist."

    # The requested input archive must exist and must actually contain the supplied recording.
    test_archive = os.path.join(INCOMING_DIR, "test_batch.zip")
    assert os.path.isfile(test_archive), f"Required archive {test_archive} does not exist."
    assert zipfile.is_zipfile(test_archive), f"{test_archive} is not a valid zip archive."
    with open(SOURCE_AUDIO, "rb") as source_file:
        source_bytes = source_file.read()
    with zipfile.ZipFile(test_archive) as archive:
        matching_members = [
            name for name in archive.namelist()
            if not name.endswith("/") and archive.read(name) == source_bytes
        ]
    assert matching_members, "test_batch.zip does not contain the supplied /app/field_note.wav recording."

    initial_data = get_dataset()
    validate_dataset_and_files(initial_data)

    # Tie the expected bird transcript to audio actually standardized from field_note.wav.
    reference_samples = decoded_pcm(SOURCE_AUDIO)
    matching_source_entries = []
    for filename, transcript in initial_data.items():
        path = os.path.join(PROCESSED_DIR, filename)
        if audio_matches_source(path, reference_samples):
            matching_source_entries.append((filename, transcript))
    assert matching_source_entries, "No API entry refers to standardized audio derived from /app/field_note.wav."
    assert any(
        "blue-winged warbler" in transcript.lower() and "northern creek" in transcript.lower()
        for _, transcript in matching_source_entries
    ), "The transcript associated with the processed field_note.wav does not contain the expected phrases."

    # Submit an unpredictable archive after the verifier starts. This checks that the
    # running daemon continues to watch, extract, standardize, transcribe, and publish.
    token = secrets.token_hex(8)
    frame_count = 22050 + secrets.randbelow(11025)
    challenge_wav = f"/tmp/verifier_silence_{token}.wav"
    with wave.open(challenge_wav, "wb") as wav_file:
        wav_file.setnchannels(2)
        wav_file.setsampwidth(2)
        wav_file.setframerate(22050)
        wav_file.writeframes(b"\x00\x00\x00\x00" * frame_count)

    temporary_archive = os.path.join(INCOMING_DIR, f".verifier_{token}.tmp")
    challenge_archive = os.path.join(INCOMING_DIR, f"verifier_{token}.zip")
    with zipfile.ZipFile(temporary_archive, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.write(challenge_wav, arcname=f"nested/challenge_{token}.wav")
    os.replace(temporary_archive, challenge_archive)

    initial_keys = set(initial_data)
    deadline = time.time() + 120
    challenge_entry = None
    latest_data = initial_data
    while time.time() < deadline:
        latest_data = get_dataset()
        for filename in set(latest_data) - initial_keys:
            path = os.path.join(PROCESSED_DIR, filename)
            if not os.path.isfile(path):
                continue
            samples = decoded_pcm(path)
            expected_samples = round(frame_count * 16000 / 22050)
            if abs(len(samples) - expected_samples) <= 1600 and samples and max(abs(int(v)) for v in samples) <= 2:
                challenge_entry = (filename, latest_data[filename])
                break
        if challenge_entry:
            break
        time.sleep(2)

    assert challenge_entry is not None, "The running daemon did not process the new verifier archive within 120 seconds."
    challenge_filename, challenge_transcript = challenge_entry
    assert isinstance(challenge_transcript, str), "The challenge transcription is not a string."
    assert challenge_transcript.strip() == "", "Whisper should return an empty transcription for the generated silent recording."

    # Re-run all original API, filename, hash, and WAV-property assertions on the updated state.
    validate_dataset_and_files(latest_data)


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-x", "--tb=short"]))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
