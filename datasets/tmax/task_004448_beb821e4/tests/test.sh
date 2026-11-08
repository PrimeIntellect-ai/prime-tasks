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
import io
import os
import random
import string
import struct
import wave

import pytest
import requests

URL = "http://127.0.0.1:8000/analyze"


def expected_extraction(audio_data):
    with wave.open(io.BytesIO(audio_data), "rb") as wav:
        assert wav.getnchannels() == 1
        assert wav.getsampwidth() == 2
        frames = wav.readframes(wav.getnframes())
    samples = struct.unpack("<{}h".format(len(frames) // 2), frames)
    length = len(samples)
    extracted = bytes((samples[(i * 100_000) % length] & 0xFF) for i in range(25))
    return extracted.decode("utf-8", errors="replace")


def make_test_wav(payload, sample_count):
    samples = [0] * sample_count
    indices = [(i * 100_000) % sample_count for i in range(25)]
    assert len(set(indices)) == 25
    for index, value in zip(indices, payload):
        samples[index] = value

    output = io.BytesIO()
    with wave.open(output, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(44100)
        wav.writeframes(struct.pack("<{}h".format(sample_count), *samples))
    return output.getvalue()


def post_audio(audio_data):
    try:
        response = requests.post(URL, data=audio_data, timeout=5)
    except requests.exceptions.ConnectionError:
        pytest.fail("Failed to connect to the extraction service at 127.0.0.1:8000. Is the server running?")
    except requests.exceptions.Timeout:
        pytest.fail("The request to the extraction service timed out.")
    except Exception as exc:
        pytest.fail(f"An unexpected error occurred while connecting to the service: {exc}")

    assert response.status_code == 200, (
        f"Expected HTTP 200 OK, but got {response.status_code}. "
        f"Response body: {response.text!r}"
    )
    return response.text.strip()


def test_extraction_service():
    audio_path = "/app/suspicious_audio.wav"
    assert os.path.isfile(audio_path), f"File {audio_path} is missing."

    with open(audio_path, "rb") as audio_file:
        captured_audio = audio_file.read()

    assert post_audio(captured_audio) == expected_extraction(captured_audio)

    rng = random.SystemRandom()
    alphabet = string.ascii_letters + string.digits
    for sample_count in (100003, 65537):
        payload = "".join(rng.choice(alphabet) for _ in range(25)).encode("ascii")
        audio_data = make_test_wav(payload, sample_count)
        expected = expected_extraction(audio_data)
        assert expected == payload.decode("ascii")
        actual = post_audio(audio_data)
        assert actual == expected, f"Expected response {expected!r}, but got {actual!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
