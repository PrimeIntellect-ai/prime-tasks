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
import json
import math
import os
import re
import secrets
import shutil
import subprocess
import wave

import pytest
import requests

PIPELINE = "/home/user/pipeline.sh"
METRICS = "/home/user/metrics.csv"
SUMMARY = "/home/user/summary.json"
SERVER = "/home/user/server.sh"
AUDIO = "/app/test_signal.wav"
REFERENCE = [10, 20, 10, 20, 10, 20, 10, 20, 10, 20]


def run_pipeline(times=1):
    for _ in range(times):
        try:
            subprocess.run([PIPELINE], check=True, timeout=30)
        except subprocess.CalledProcessError as exc:
            pytest.fail(f"Pipeline script failed to execute successfully: {exc}")
        except subprocess.TimeoutExpired:
            pytest.fail("Pipeline script execution timed out.")


def expected_metrics(path):
    values = []
    for second in range(10):
        proc = subprocess.run(
            [
                "ffmpeg", "-hide_banner", "-nostats", "-i", path,
                "-ss", str(second), "-t", "1", "-af", "volumedetect",
                "-f", "null", "-",
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
        matches = re.findall(r"mean_volume:\s*(-?(?:\d+(?:\.\d*)?|\.\d+))\s*dB", proc.stderr)
        if not matches:
            db = -90.0
        else:
            db = float(matches[-1])
        values.append((db + 90.0) * 100.0 / 90.0)
    return values


def read_and_validate_outputs(expected):
    assert os.path.isfile(METRICS), f"{METRICS} was not created."
    with open(METRICS, "r", encoding="utf-8") as handle:
        lines = [line.strip() for line in handle if line.strip()]
    assert len(lines) == 10, f"Expected exactly 10 records, but found {len(lines)}."

    by_timestamp = {}
    for line in lines:
        fields = [field.strip() for field in line.split(",")]
        assert len(fields) == 2, f"Invalid metrics.csv record: {line!r}"
        try:
            timestamp = float(fields[0])
            value = float(fields[1])
        except ValueError:
            pytest.fail(f"Non-numeric metrics.csv record: {line!r}")
        assert math.isfinite(timestamp) and math.isfinite(value), f"Non-finite record: {line!r}"
        assert timestamp.is_integer(), f"Timestamp must identify a whole second: {fields[0]!r}"
        timestamp = int(timestamp)
        assert timestamp not in by_timestamp, f"Duplicate timestamp {timestamp}."
        by_timestamp[timestamp] = value

    assert set(by_timestamp) == set(range(10)), "Timestamps must be exactly seconds 0 through 9."
    actual = [by_timestamp[i] for i in range(10)]
    for second, (got, wanted) in enumerate(zip(actual, expected)):
        assert 0.0 <= got <= 100.0, f"Normalized value for second {second} is outside 0..100: {got}"
        assert math.isclose(got, wanted, abs_tol=0.35), (
            f"Second {second} has normalized value {got}, expected {wanted:.4f} from the audio."
        )

    assert os.path.isfile(SUMMARY), f"{SUMMARY} does not exist."
    try:
        with open(SUMMARY, "r", encoding="utf-8") as handle:
            data = json.load(handle)
    except json.JSONDecodeError:
        pytest.fail(f"{SUMMARY} does not contain valid JSON.")

    assert "average_volume" in data, "Missing 'average_volume' in summary.json."
    assert "euclidean_distance" in data, "Missing 'euclidean_distance' in summary.json."
    assert "record_count" in data, "Missing 'record_count' in summary.json."
    assert int(data["record_count"]) == 10, f"Expected record_count to be 10, got {data['record_count']}."

    try:
        average = float(data["average_volume"])
        distance = float(data["euclidean_distance"])
    except (TypeError, ValueError):
        pytest.fail("Summary aggregate values must be numeric.")
    assert math.isfinite(average) and math.isfinite(distance), "Summary values must be finite."

    wanted_average = sum(actual) / 10.0
    wanted_distance = math.sqrt(sum((actual[i] - REFERENCE[i]) ** 2 for i in range(10)))
    assert math.isclose(average, wanted_average, abs_tol=0.15), (
        f"average_volume {average} does not match metrics.csv value {wanted_average}."
    )
    assert math.isclose(distance, wanted_distance, abs_tol=0.15), (
        f"euclidean_distance {distance} does not match metrics.csv value {wanted_distance}."
    )


def make_unpredictable_short_audio(path):
    rate = 44100
    rng = secrets.SystemRandom()
    amplitudes = [rng.randint(2500, 22000) for _ in range(6)]
    frequencies = [rng.randint(240, 1800) for _ in range(6)]
    with wave.open(path, "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(rate)
        phase = 0.0
        for amplitude, frequency in zip(amplitudes, frequencies):
            step = 2.0 * math.pi * frequency / rate
            frames = bytearray()
            for _ in range(rate):
                sample = int(amplitude * math.sin(phase))
                frames.extend(sample.to_bytes(2, byteorder="little", signed=True))
                phase += step
            output.writeframes(frames)


def test_complete_pipeline_and_http_behavior():
    assert os.path.isfile(PIPELINE), f"{PIPELINE} does not exist."
    assert os.access(PIPELINE, os.X_OK), f"{PIPELINE} is not executable."
    assert os.path.isfile(SERVER), f"{SERVER} does not exist."
    assert os.access(SERVER, os.X_OK), f"{SERVER} is not executable."

    # Validate extraction against the supplied recording.
    original_expected = expected_metrics(AUDIO)
    run_pipeline()
    read_and_validate_outputs(original_expected)

    # Replace the input temporarily with an unpredictable six-second recording.
    # Correct pipelines must extract its values, gap-fill seconds 6..9, and remain
    # deduplicated after the scheduler invokes them twice.
    backup = "/tmp/test_signal.original.wav"
    shutil.copy2(AUDIO, backup)
    try:
        make_unpredictable_short_audio(AUDIO)
        challenge_expected = expected_metrics(AUDIO)
        assert challenge_expected[6:] == [0.0, 0.0, 0.0, 0.0]
        run_pipeline(times=2)
        read_and_validate_outputs(challenge_expected)
    finally:
        shutil.copy2(backup, AUDIO)

    try:
        response = requests.get("http://127.0.0.1:8080/api/v1/metrics", timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the HTTP server on port 8080 or request failed: {exc}")

    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}."
    content_type = response.headers.get("Content-Type", "")
    assert "application/json" in content_type, (
        f"Expected Content-Type to contain application/json, got {content_type}."
    )
    with open(SUMMARY, "rb") as handle:
        summary_body = handle.read()
    assert response.content == summary_body, "HTTP response body is not the exact contents of summary.json."
    try:
        api_data = response.json()
    except ValueError:
        pytest.fail(f"API response body is not valid JSON. Response text: {response.text}")
    assert "average_volume" in api_data, "Missing 'average_volume' in API JSON response."
    assert "euclidean_distance" in api_data, "Missing 'euclidean_distance' in API JSON response."
    assert "record_count" in api_data, "Missing 'record_count' in API JSON response."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
