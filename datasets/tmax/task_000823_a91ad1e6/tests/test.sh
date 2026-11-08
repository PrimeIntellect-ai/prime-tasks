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
REWARD=0
trap 'printf "%s\n" "$REWARD" > /logs/verifier/reward.txt' EXIT

# Preserve the legacy processor and instrument its required use by the service.
python3 - <<'PY'
from pathlib import Path
p = Path('/app/config_processor')
assert p.is_file(), '/app/config_processor does not exist'
assert p.read_bytes()[:4] == b'\x7fELF', '/app/config_processor is not the supplied binary'
PY
rm -rf /tmp/verifier_cp_calls
mkdir -p /tmp/verifier_cp_calls
mv /app/config_processor /app/config_processor.verifier-original
cat > /app/config_processor <<'WRAPPER_EOF'
#!/bin/bash
set -e
tmp=$(mktemp /tmp/verifier_cp_calls/call.XXXXXX)
cat > "$tmp"
exec /app/config_processor.verifier-original < "$tmp"
WRAPPER_EOF
chmod 755 /app/config_processor

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import io
import os
import random
import secrets
import subprocess
from collections import Counter, defaultdict

import pytest
import requests

URL = "http://127.0.0.1:9090/process"


def test_health_check_script():
    """Verify /app/health_check.sh exists, is executable, and works."""
    script_path = "/app/health_check.sh"
    assert os.path.exists(script_path), f"{script_path} does not exist"
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable"

    if os.path.exists("/tmp/health.log"):
        os.remove("/tmp/health.log")

    subprocess.run([script_path], check=True)

    assert os.path.exists("/tmp/health.log"), "/tmp/health.log was not created by the health check script"
    with open("/tmp/health.log", "r") as f:
        content = f.read().strip()
    assert "OK" in content, f"Expected 'OK' in /tmp/health.log, got '{content}'"


def test_cron_job_exists():
    """Verify the cron job is scheduled every 5 minutes."""
    try:
        result = subprocess.run(["crontab", "-l", "-u", "user"], capture_output=True, text=True)
        cron_output = result.stdout
    except Exception:
        result = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
        cron_output = result.stdout

    assert "/app/health_check.sh" in cron_output, "Cron job for /app/health_check.sh not found"

    valid_schedules = ["*/5", "0,5,10,15,20,25,30,35,40,45,50,55"]
    found_schedule = False
    for line in cron_output.splitlines():
        if "/app/health_check.sh" in line and not line.strip().startswith("#"):
            parts = line.strip().split()
            if parts[0] in valid_schedules:
                found_schedule = True
                break

    assert found_schedule, "Cron job is not scheduled to run every 5 minutes (expected */5 in minute field)"


def test_http_service_processing():
    """Verify the HTTP service processes encodings, cleans newlines, and gap-fills."""
    csv_data = '1000,key1,"hello\nworld"\n1120,key1,"test"\n'
    payload = csv_data.encode("utf-16le")

    try:
        response = requests.post(URL, data=payload, headers={"Content-Type": "text/csv"}, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to HTTP service at {URL}: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}"

    result_text = response.text.strip()
    lines = result_text.splitlines()
    expected_lines = [
        '1000,key1,"hello world"',
        '1060,key1,"hello world"',
        '1120,key1,"test"'
    ]
    result_clean = [line.replace('"', '') for line in lines]
    expected_clean = [line.replace('"', '') for line in expected_lines]
    for expected in expected_clean:
        assert expected in result_clean, f"Expected line '{expected}' not found in output: {result_clean}"


def test_http_service_iso8859_1():
    """Verify the HTTP service handles ISO-8859-1 encoding."""
    csv_data = '2000,key2,"café"\n2060,key2,"done"\n'
    payload = csv_data.encode("iso-8859-1")

    try:
        response = requests.post(URL, data=payload, headers={"Content-Type": "text/csv"}, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to HTTP service at {URL}: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}"
    result_text = response.text.strip()
    assert "café" in result_text or "caf\u00e9" in result_text, f"Failed to properly decode ISO-8859-1 payload. Output: {result_text}"


def encode_csv(records, encoding):
    out = io.StringIO(newline="")
    writer = csv.writer(out, lineterminator="\n")
    writer.writerows(records)
    return out.getvalue().encode(encoding)


def parse_csv_bytes(data):
    text = data.decode("utf-8")
    return [tuple(row) for row in csv.reader(io.StringIO(text, newline="")) if row]


def expected_resample(records):
    by_key = defaultdict(list)
    for timestamp, key, value in records:
        by_key[key].append((int(timestamp), value.replace("\n", " ").replace("\r", " ")))

    result = []
    for key, samples in by_key.items():
        samples.sort()
        values = dict(samples)
        current = None
        for timestamp in range(samples[0][0], samples[-1][0] + 1, 60):
            if timestamp in values:
                current = values[timestamp]
            result.append((str(timestamp), key, current))
    return result


def assert_complete_response(response, expected):
    assert response.status_code == 200, response.text
    actual = parse_csv_bytes(response.content)
    assert all(len(row) == 3 for row in actual), f"Malformed CSV response: {actual}"
    assert Counter(actual) == Counter(expected), f"Expected exactly {expected}, got {actual}"

    grouped = defaultdict(list)
    for timestamp, key, _ in actual:
        grouped[key].append(int(timestamp))
    for timestamps in grouped.values():
        timestamps.sort()
        assert all(b - a == 60 for a, b in zip(timestamps, timestamps[1:])), timestamps


def assert_processor_received(before, cleaned_records):
    after = set(glob.glob("/tmp/verifier_cp_calls/call.*"))
    new_calls = after - before
    assert new_calls, "The service did not pass the request through /app/config_processor"
    wanted = [(str(t), str(k), v.replace("\n", " ").replace("\r", " ")) for t, k, v in cleaned_records]
    captured = []
    for path in new_calls:
        with open(path, "rb") as f:
            raw = f.read()
        assert b"\x00" not in raw, "The processor received unconverted UTF-16 data"
        try:
            rows = parse_csv_bytes(raw)
        except Exception as exc:
            pytest.fail(f"The processor did not receive valid UTF-8 CSV: {exc}")
        captured.append(rows)
    assert any(Counter(rows) == Counter(wanted) for rows in captured), \
        f"Processor did not receive the decoded, newline-cleaned CSV; captured {captured}"


def send_and_verify(records, encoding):
    before = set(glob.glob("/tmp/verifier_cp_calls/call.*"))
    payload = encode_csv(records, encoding)
    response = requests.post(URL, data=payload, headers={"Content-Type": "text/csv"}, timeout=8)
    expected = expected_resample(records)
    assert_complete_response(response, expected)
    assert_processor_received(before, records)


def test_randomized_general_pipeline_and_sequential_requests():
    rng = random.SystemRandom()
    token = secrets.token_hex(8)
    base = rng.randrange(25_000_000, 35_000_000) // 60 * 60 + rng.randrange(0, 60)
    key_a = "alpha_" + token
    key_b = "beta_" + token
    gap_a = rng.choice([2, 3, 4])
    final_a = gap_a + rng.choice([2, 3])
    final_b = 1 + rng.choice([2, 3, 4])

    utf16_records = [
        (base, key_a, f'north,{token}\n"south"'),
        (base + 60, key_b, f"begin-{token}"),
        (base + 60 * gap_a, key_a, f"middle,{token}"),
        (base + 60 * final_b, key_b, f"finish-{token}"),
        (base + 60 * final_a, key_a, f"last-{token}"),
    ]
    utf16_records.sort(key=lambda row: (row[0], row[1]))
    send_and_verify(utf16_records, "utf-16le")

    # A different request and encoding must have an exact independent response.
    iso_base = base + 100_000
    iso_key1 = "latin_" + token
    iso_key2 = "other_" + token
    iso_records = [
        (iso_base, iso_key1, f"café-{token}"),
        (iso_base + 60, iso_key2, f"piñata-{token}"),
        (iso_base + 180, iso_key1, f"mañana-{token}"),
        (iso_base + 240, iso_key2, f"final-{token}"),
    ]
    send_and_verify(iso_records, "iso-8859-1")

    # Exercise a third sequential request and ensure no rows from prior requests leak.
    third_base = iso_base + 200_000
    third_records = [
        (third_base, "third_" + token, f"only,{token}"),
        (third_base + 120, "third_" + token, f"done-{token}"),
    ]
    send_and_verify(third_records, "utf-8")


def test_only_required_route_and_method_are_accepted():
    get_response = requests.get(URL, timeout=5)
    wrong_path = requests.post("http://127.0.0.1:9090/not-process", data=b"1,k,v\n", timeout=5)
    assert get_response.status_code != 200, "GET /process must not be treated as a processing request"
    assert wrong_path.status_code != 200, "POST requests to routes other than /process must not be processed"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    REWARD=1
fi
