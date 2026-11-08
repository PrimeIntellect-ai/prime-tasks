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

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import concurrent.futures
import json
import pathlib
import re
import secrets
import subprocess
import wave

import pytest
import requests

BASE_URL = "http://127.0.0.1:8000"
AUTH_HEADER = {"Authorization": "Bearer debug-admin-123"}


def request_transcription(path, timeout=30):
    response = requests.post(
        f"{BASE_URL}/transcribe",
        headers=AUTH_HEADER,
        json={"file": str(path)},
        timeout=timeout,
    )
    assert response.status_code == 200, (
        f"Expected 200 for {path}, got {response.status_code}: {response.text}"
    )
    try:
        data = response.json()
    except json.JSONDecodeError:
        pytest.fail(f"Response was not valid JSON: {response.text}")
    assert isinstance(data, dict) and "transcript" in data
    assert isinstance(data["transcript"], str)
    return data["transcript"]


def normalize(text):
    number_aliases = {
        "1": "one", "2": "two", "3": "three", "4": "four",
        "5": "five", "6": "six", "7": "seven", "8": "eight",
        "9": "nine",
    }
    return [number_aliases.get(word, word) for word in re.findall(r"[a-z0-9]+", text.lower())]


def make_corrupt_wav(destination, phrase, corruption):
    clean = destination.with_suffix(".clean.wav")
    subprocess.run(
        ["espeak", "-s", "145", "-w", str(clean), phrase],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    data = bytearray(clean.read_bytes())
    clean.unlink()

    assert data[:4] == b"RIFF"
    data_offset = data.find(b"data")
    assert data_offset >= 0 and data_offset + 8 <= len(data)

    if corruption in ("riff-zero", "both-zero"):
        data[4:8] = b"\x00" * 4
    if corruption in ("data-zero", "both-zero"):
        data[data_offset + 4:data_offset + 8] = b"\x00" * 4
    destination.write_bytes(data)


@pytest.fixture(scope="module")
def generated_audio(tmp_path_factory):
    root = tmp_path_factory.mktemp("hidden_audio")
    colors = ["red", "blue", "green", "white", "black", "yellow"]
    animals = ["rabbit", "tiger", "monkey", "panda", "falcon", "otter"]
    numbers = ["one", "two", "three", "five", "six", "seven", "eight"]

    choices = []
    used = set()
    for index, corruption in enumerate(("riff-zero", "data-zero", "both-zero")):
        while True:
            phrase = f"the {secrets.choice(colors)} {secrets.choice(animals)} has {secrets.choice(numbers)} tickets"
            if phrase not in used:
                used.add(phrase)
                break
        path = root / f"sample_{secrets.token_hex(8)}_{index}.wav"
        make_corrupt_wav(path, phrase, corruption)
        choices.append((path, normalize(phrase)))
    return choices


def test_auth_required():
    try:
        response = requests.post(
            f"{BASE_URL}/transcribe",
            json={"file": "/app/corrupt_diag.wav"},
            timeout=2,
        )
    except requests.RequestException as exc:
        pytest.fail(f"Failed to connect to the service: {exc}")
    assert response.status_code == 401, f"Expected 401 Unauthorized, got {response.status_code}"


def test_transcribe_corrupt_wav():
    transcript = request_transcription("/app/corrupt_diag.wav")
    words = re.findall(r"[a-z0-9]+", transcript.lower())
    assert "system" in words, f"Transcript did not contain 'system': {transcript}"
    assert "failure" in words, f"Transcript did not contain 'failure': {transcript}"
    assert "code" in words, f"Transcript did not contain 'code': {transcript}"
    assert "bravo" in words, f"Transcript did not contain 'bravo': {transcript}"
    assert "niner" in words or "9" in words or "nine" in words, (
        f"Transcript did not contain 'niner' or '9': {transcript}"
    )
    assert "four" in words or "4" in words, (
        f"Transcript did not contain 'four' or '4': {transcript}"
    )


def test_varied_corrupt_wavs_are_actually_transcribed(generated_audio):
    returned = []
    for path, expected_words in generated_audio:
        transcript = request_transcription(path)
        actual_words = normalize(transcript)
        assert actual_words == expected_words, (
            f"Incorrect transcription for a verifier-generated corrupted WAV. "
            f"Expected {expected_words}, got {actual_words}"
        )
        returned.append(tuple(actual_words))
    assert len(set(returned)) == len(returned), "Distinct audio files returned identical content"


def test_concurrent_requests_no_deadlock_and_valid_results(generated_audio):
    audio_path, expected_words = generated_audio[0]
    initial = requests.get(f"{BASE_URL}/metrics", timeout=3)
    assert initial.status_code == 200
    initial_data = initial.json()
    assert isinstance(initial_data.get("count"), int)

    barrier = concurrent.futures.thread.Barrier(20)

    def make_get():
        barrier.wait(timeout=5)
        response = requests.get(f"{BASE_URL}/metrics", timeout=5)
        assert response.status_code == 200
        payload = response.json()
        assert isinstance(payload.get("count"), int)
        return "get"

    def make_post():
        barrier.wait(timeout=5)
        response = requests.post(
            f"{BASE_URL}/transcribe",
            headers=AUTH_HEADER,
            json={"file": str(audio_path)},
            timeout=5,
        )
        assert response.status_code == 200
        payload = response.json()
        assert normalize(payload.get("transcript", "")) == expected_words
        return "post"

    tasks = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=20) as executor:
        for _ in range(10):
            tasks.append(executor.submit(make_get))
            tasks.append(executor.submit(make_post))
        try:
            results = [task.result(timeout=10) for task in tasks]
        except concurrent.futures.TimeoutError:
            pytest.fail("Server deadlocked or timed out under concurrent load")

    assert len(results) == 20, "Not all concurrent requests completed"
    assert results.count("post") == 10 and results.count("get") == 10

    final = requests.get(f"{BASE_URL}/metrics", timeout=3)
    assert final.status_code == 200
    final_count = final.json().get("count")
    assert isinstance(final_count, int)
    assert final_count >= initial_data["count"] + 10, "Successful transcriptions were not counted"


def test_zero_duration_is_rejected_and_server_survives(tmp_path):
    empty = tmp_path / "zero_duration.wav"
    with wave.open(str(empty), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(16000)
        output.writeframes(b"")

    try:
        response = requests.post(
            f"{BASE_URL}/transcribe",
            headers=AUTH_HEADER,
            json={"file": str(empty)},
            timeout=5,
        )
        assert response.status_code >= 400, "A zero-duration stream was accepted"
    except requests.RequestException:
        # An uncaught AssertionError may close this request; the service must remain alive.
        pass

    health = requests.get(f"{BASE_URL}/metrics", timeout=3)
    assert health.status_code == 200


def test_recovered_source_and_positive_duration_assertion_exist():
    roots = (pathlib.Path("/app"), pathlib.Path("/home/user"))
    candidates = []
    for root in roots:
        if root.exists():
            candidates.extend(path for path in root.rglob("*.py") if path.is_file())

    valid_source = []
    for path in candidates:
        try:
            text = path.read_text(errors="strict")
            if "/transcribe" not in text or "debug-admin-123" not in text:
                continue
            tree = ast.parse(text, filename=str(path))
            compile(tree, str(path), "exec")
        except (OSError, UnicodeError, SyntaxError):
            continue

        has_duration_assert = False
        for node in ast.walk(tree):
            if not isinstance(node, ast.Assert) or not isinstance(node.test, ast.Compare):
                continue
            comparison = node.test
            if len(comparison.ops) != 1 or not isinstance(comparison.ops[0], ast.Gt):
                continue
            if len(comparison.comparators) != 1:
                continue
            right = comparison.comparators[0]
            if not isinstance(right, ast.Constant) or right.value not in (0, 0.0):
                continue
            left_text = ast.get_source_segment(text, comparison.left) or ""
            if "duration" in left_text.lower():
                has_duration_assert = True
                break

        if has_duration_assert:
            valid_source.append(path)

    assert valid_source, (
        "No recovered, Python-compatible service source containing the required "
        "strict positive-duration assertion was found"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
