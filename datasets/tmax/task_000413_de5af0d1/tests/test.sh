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
import re
import subprocess
from datetime import datetime, timezone, timedelta

import requests

ROOT = "/app/bash-http-scheduler"
URL = "http://127.0.0.1:8080/schedule"
HEADERS = {"Content-Type": "application/x-www-form-urlencoded"}
TS_RE = re.compile(r"(?<!\d)\d{10}(?!\d)")


def next_utc_midnight(instant):
    return datetime.combine(
        instant.date() + timedelta(days=1),
        datetime.min.time(),
        tzinfo=timezone.utc,
    )


def timestamps(text):
    return {int(value) for value in TS_RE.findall(text.strip())}


def post(payload):
    try:
        return requests.post(URL, data=payload, headers=HEADERS, timeout=5)
    except requests.exceptions.RequestException as exc:
        assert False, f"Failed to connect to the service on port 8080: {exc}"


def test_service_running_and_correct_utc_timestamp():
    now = datetime.now(timezone.utc)

    # Exercise an ordinary future UTC time when one is safely available today.
    target = (now + timedelta(minutes=10)).replace(second=0, microsecond=0)
    if target.date() == now.date():
        value = target.strftime("%H:%M")
        response = post(f"time={value}&job=test")
        assert response.status_code == 200, (
            f"Expected 200 OK for future UTC time {value}, got "
            f"{response.status_code}. Response: {response.text}"
        )
        found = timestamps(response.text)
        assert found, f"Response does not contain a valid 10-digit Unix timestamp: {response.text.strip()}"
        expected = int(target.timestamp())
        assert expected in found, (
            f"Expected Unix timestamp {expected} for UTC time {value}, "
            f"got: {response.text.strip()}"
        )

    # A time that has already passed today must not be accepted as a future job.
    past = (now - timedelta(minutes=10)).replace(second=0, microsecond=0)
    if past.date() == now.date():
        value = past.strftime("%H:%M")
        response = post(f"time={value}&job=test")
        assert response.status_code == 400, (
            f"Expected 400 for past UTC time {value}, got {response.status_code}. "
            f"Response: {response.text}"
        )


def test_boundary_condition_fix():
    before = datetime.now(timezone.utc)
    response = post("time=24:00&job=test")
    after = datetime.now(timezone.utc)

    assert response.status_code == 200, (
        "Expected 200 OK for boundary time (24:00), got "
        f"{response.status_code}. Response: {response.text}"
    )
    found = timestamps(response.text)
    assert found, f"Response does not contain a valid 10-digit Unix timestamp: {response.text.strip()}"

    # Include both candidates only to avoid a false failure if the request crosses UTC midnight.
    expected = {
        int(next_utc_midnight(before).timestamp()),
        int(next_utc_midnight(after).timestamp()),
    }
    assert found & expected, (
        f"24:00 should resolve to the next UTC midnight {sorted(expected)}, "
        f"got: {response.text.strip()}"
    )


def test_process_uses_utc_even_with_non_utc_local_timezone():
    process = os.path.join(ROOT, "process.sh")
    assert os.path.isfile(process), f"File {process} is missing."
    assert os.access(process, os.X_OK), f"File {process} is not executable."

    # Execute the processor under non-UTC local timezones. Its result must still
    # be the Unix timestamp for 24:00 UTC, not local midnight.
    for tz in ("America/Los_Angeles", "Asia/Tokyo"):
        env = os.environ.copy()
        env["TZ"] = tz
        before = datetime.now(timezone.utc)
        result = subprocess.run(
            [process, "24:00", "timezone-test"],
            cwd=ROOT,
            env=env,
            text=True,
            capture_output=True,
            timeout=5,
        )
        after = datetime.now(timezone.utc)
        assert result.returncode == 0, (
            f"process.sh rejected 24:00 when local TZ={tz}: "
            f"stdout={result.stdout!r}, stderr={result.stderr!r}"
        )
        found = timestamps(result.stdout)
        assert found, f"process.sh did not return a Unix timestamp for TZ={tz}: {result.stdout!r}"
        expected = {
            int(next_utc_midnight(before).timestamp()),
            int(next_utc_midnight(after).timestamp()),
        }
        assert found & expected, (
            f"process.sh interpreted 24:00 using TZ={tz}; expected UTC timestamp "
            f"{sorted(expected)}, got {result.stdout.strip()!r}"
        )


def test_process_sh_fixes_applied():
    path = os.path.join(ROOT, "process.sh")
    assert os.path.isfile(path), f"File {path} is missing."

    with open(path, "r") as handle:
        content = handle.read()

    # Preserve the source-level checks while behavioral tests verify the result.
    assert 'UTC"' in content or "UTC" in content, (
        "The timezone parsing bug does not appear to be fixed "
        "(missing 'UTC' in date command)."
    )
    assert "-gt 86400" in content or "-ge 86401" in content or "-ge 86400" not in content, (
        "The boundary condition assertion (-ge 86400) does not appear to be fixed."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
