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
import random
import requests
import pytest

RAW_DATA = "/home/user/data/raw_data.csv"
CLEAN_DATA = "/home/user/data/clean_data.csv"
URL_BASE = "http://localhost:8888/payload/"


def is_clean(f1, f2, f3):
    return (3.0 * f1) - (2.0 * f2) + f3 <= 100.0


@pytest.fixture(scope="module")
def sample_data():
    clean_samples = []
    dirty_samples = []

    if not os.path.exists(RAW_DATA):
        pytest.fail(f"Raw data file {RAW_DATA} is missing.")

    with open(RAW_DATA, "r") as f:
        for line in f:
            parts = line.strip().split(",")
            if len(parts) == 5:
                row_id = parts[0]
                try:
                    f1, f2, f3 = float(parts[1]), float(parts[2]), float(parts[3])
                except ValueError:
                    continue

                payload = parts[4]

                if is_clean(f1, f2, f3):
                    if len(clean_samples) < 5:
                        clean_samples.append((row_id, payload))
                else:
                    if len(dirty_samples) < 5:
                        dirty_samples.append((row_id, payload))

            if len(clean_samples) >= 5 and len(dirty_samples) >= 5:
                break

    return clean_samples, dirty_samples


@pytest.fixture(scope="module")
def random_samples():
    rng = random.SystemRandom()
    clean_samples = []
    dirty_samples = []
    clean_seen = 0
    dirty_seen = 0
    sample_size = 12

    with open(RAW_DATA, "r") as f:
        for line in f:
            parts = line.rstrip("\n").split(",")
            if len(parts) != 5:
                continue
            try:
                f1, f2, f3 = float(parts[1]), float(parts[2]), float(parts[3])
            except ValueError:
                continue

            item = (parts[0], parts[4])
            if is_clean(f1, f2, f3):
                clean_seen += 1
                if len(clean_samples) < sample_size:
                    clean_samples.append(item)
                else:
                    replacement = rng.randrange(clean_seen)
                    if replacement < sample_size:
                        clean_samples[replacement] = item
            else:
                dirty_seen += 1
                if len(dirty_samples) < sample_size:
                    dirty_samples.append(item)
                else:
                    replacement = rng.randrange(dirty_seen)
                    if replacement < sample_size:
                        dirty_samples[replacement] = item

    assert len(clean_samples) == sample_size, "Not enough clean rows to sample"
    assert len(dirty_samples) == sample_size, "Not enough dirty rows to sample"
    return clean_samples, dirty_samples


def test_clean_data_file_exists():
    assert os.path.exists(CLEAN_DATA), f"Missing cleaned data file at {CLEAN_DATA}"
    assert os.path.isfile(CLEAN_DATA), f"{CLEAN_DATA} is not a file"
    assert os.path.getsize(CLEAN_DATA) > 0, f"{CLEAN_DATA} is empty"


def test_clean_data_is_complete_and_exact():
    expected_count = 0
    actual_count = 0

    with open(RAW_DATA, "r") as raw, open(CLEAN_DATA, "r") as cleaned:
        for raw_line_number, raw_line in enumerate(raw, 1):
            parts = raw_line.rstrip("\n").split(",")
            assert len(parts) == 5, f"Malformed raw row at line {raw_line_number}"
            try:
                f1, f2, f3 = float(parts[1]), float(parts[2]), float(parts[3])
            except ValueError:
                pytest.fail(f"Non-numeric feature at raw line {raw_line_number}")

            if is_clean(f1, f2, f3):
                expected_count += 1
                actual_line = cleaned.readline()
                actual_count += 1 if actual_line else 0
                assert actual_line == raw_line, (
                    f"clean_data.csv differs from the required filtered dataset "
                    f"at clean row {expected_count} (source line {raw_line_number})"
                )

        extra_line = cleaned.readline()
        assert extra_line == "", "clean_data.csv contains extra or dirty rows"

    assert expected_count > 0, "No clean rows found in raw_data.csv"
    assert actual_count == expected_count, (
        f"Expected {expected_count} clean rows, found only {actual_count}"
    )


def test_api_clean_records(sample_data):
    clean_samples, _ = sample_data
    assert len(clean_samples) > 0, "No clean samples found in raw_data.csv"

    for row_id, expected_payload in clean_samples:
        try:
            resp = requests.get(f"{URL_BASE}{row_id}", timeout=2)
        except requests.exceptions.RequestException as e:
            pytest.fail(f"Failed to connect to API for clean ID {row_id}: {e}")

        assert resp.status_code == 200, f"Expected 200 OK for clean ID {row_id}, got {resp.status_code}. Response: {resp.text}"
        assert expected_payload in resp.text, f"Expected payload '{expected_payload}' for ID {row_id}, but got: {resp.text}"


def test_api_dirty_records(sample_data):
    _, dirty_samples = sample_data
    assert len(dirty_samples) > 0, "No dirty samples found in raw_data.csv"

    for row_id, _ in dirty_samples:
        try:
            resp = requests.get(f"{URL_BASE}{row_id}", timeout=2)
        except requests.exceptions.RequestException as e:
            pytest.fail(f"Failed to connect to API for dirty ID {row_id}: {e}")

        assert resp.status_code == 404, f"Expected 404 Not Found for dirty ID {row_id}, got {resp.status_code}. Response: {resp.text}"


def test_api_random_records_across_dataset(random_samples):
    clean_samples, dirty_samples = random_samples

    for row_id, expected_payload in clean_samples:
        try:
            resp = requests.get(f"{URL_BASE}{row_id}", timeout=2)
        except requests.exceptions.RequestException as e:
            pytest.fail(f"Failed to connect to API for clean ID {row_id}: {e}")
        assert resp.status_code == 200, f"Expected 200 OK for clean ID {row_id}, got {resp.status_code}"
        assert expected_payload in resp.text, f"Expected payload '{expected_payload}' for ID {row_id}, but got: {resp.text}"

    for row_id, _ in dirty_samples:
        try:
            resp = requests.get(f"{URL_BASE}{row_id}", timeout=2)
        except requests.exceptions.RequestException as e:
            pytest.fail(f"Failed to connect to API for dirty ID {row_id}: {e}")
        assert resp.status_code == 404, f"Expected 404 Not Found for dirty ID {row_id}, got {resp.status_code}"


def test_api_nonexistent_record():
    fake_id = "999999999"
    try:
        resp = requests.get(f"{URL_BASE}{fake_id}", timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to API for non-existent ID {fake_id}: {e}")

    assert resp.status_code == 404, f"Expected 404 Not Found for non-existent ID {fake_id}, got {resp.status_code}. Response: {resp.text}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
