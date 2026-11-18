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

backup=$(mktemp)
cp /app/logs/events.log "$backup"
cleanup() {
    cp "$backup" /app/logs/events.log
    rm -f "$backup"
}
trap cleanup EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import time
import requests

LOG_PATH = "/app/logs/events.log"
API_URL = "http://127.0.0.1:8000/api/stats"


def compute_expected_stats(log_path):
    valid_latencies = []
    latest_by_level = {}

    with open(log_path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue

            # Parse line: 2023-10-25T09:00:00Z | INFO | latency=50ms | Bootup
            parts = [p.strip() for p in line.split('|')]
            if len(parts) >= 3:
                level = parts[1]
                latency_str = parts[2]

                match = re.match(r'^latency=(-?\d+)ms$', latency_str)
                if match:
                    latency_val = int(match.group(1))
                    if latency_val >= 0:
                        valid_latencies.append(latency_val)
                        latest_by_level[level] = line

    if len(valid_latencies) >= 3:
        rolling_avg_3 = sum(valid_latencies[-3:]) / 3.0
    elif len(valid_latencies) > 0:
        rolling_avg_3 = sum(valid_latencies) / float(len(valid_latencies))
    else:
        rolling_avg_3 = 0.0

    return {
        "rolling_avg_3": rolling_avg_3,
        "latest_by_level": latest_by_level
    }


def request_and_assert_expected():
    expected_data = compute_expected_stats(LOG_PATH)

    try:
        response = requests.get(
            API_URL,
            params={"verification_nonce": secrets.token_hex(8)},
            timeout=5,
            headers={"Cache-Control": "no-cache"},
        )
    except requests.exceptions.RequestException as e:
        assert False, f"Failed to connect to the API via Nginx proxy at {API_URL}: {e}"

    assert response.status_code == 200, \
        f"Expected HTTP 200, got {response.status_code}. Response: {response.text}"

    try:
        data = response.json()
    except ValueError:
        assert False, f"Response is not valid JSON: {response.text}"

    assert "rolling_avg_3" in data, "Missing 'rolling_avg_3' in JSON response."
    assert "latest_by_level" in data, "Missing 'latest_by_level' in JSON response."
    assert set(data.keys()) == {"rolling_avg_3", "latest_by_level"}, \
        f"Response contains unexpected fields: {set(data.keys())}"

    assert abs(data["rolling_avg_3"] - expected_data["rolling_avg_3"]) < 1e-5, \
        f"Expected rolling_avg_3 to be {expected_data['rolling_avg_3']}, got {data['rolling_avg_3']}."

    assert data["latest_by_level"] == expected_data["latest_by_level"], \
        f"Expected latest_by_level to be {expected_data['latest_by_level']}, got {data['latest_by_level']}."


def replace_log(lines):
    temporary = f"{LOG_PATH}.verifier-{secrets.token_hex(8)}"
    with open(temporary, "w") as f:
        f.write("\n".join(lines) + "\n")
    os.chmod(temporary, 0o666)
    os.replace(temporary, LOG_PATH)


def test_api_stats_endpoint():
    assert os.path.isfile(LOG_PATH), f"Log file {LOG_PATH} is missing."

    # Retain the original fixture assertion.
    request_and_assert_expected()

    # Replace the fixture with unpredictable values and messages. Invalid entries
    # must not affect either the rolling window or per-level latest selection.
    base = 20 + secrets.randbelow(500)
    token = secrets.token_hex(12)
    replacement = [
        f"2026-04-01T10:00:00Z | INFO | latency={base}ms | start-{token}",
        f"2026-04-01T10:01:00Z | WARN | latency=-{base + 1}ms | negative-{token}",
        f"2026-04-01T10:02:00Z | ERROR | latency={base + 17}ms | error-{token}",
        f"2026-04-01T10:03:00Z | DEBUG | latency=NaNms | nan-{token}",
        f"2026-04-01T10:04:00Z | WARN | latency={base + 43}ms | warn-{token}",
        f"2026-04-01T10:05:00Z | NOTICE | latency={base + 2}.5ms | decimal-{token}",
        f"2026-04-01T10:06:00Z | INFO | latency={base + 89}ms | latest-info-{token}",
        f"2026-04-01T10:07:00Z | TRACE | message-without-latency | missing-{token}",
    ]
    replace_log(replacement)
    request_and_assert_expected()

    # Append after a successful request to verify that every request rereads the
    # file rather than serving statistics cached from the previous contents.
    appended_latency = base + 131
    appended_line = (
        f"2026-04-01T10:08:00Z | ERROR | latency={appended_latency}ms | "
        f"appended-{secrets.token_hex(12)}"
    )
    with open(LOG_PATH, "a") as f:
        f.write(appended_line + "\n")
        f.write(f"2026-04-01T10:09:00Z | INFO | latency=-9ms | ignored-after-{token}\n")
    request_and_assert_expected()

    # Also exercise the specified behavior when fewer than three valid values exist.
    lone = 1 + secrets.randbelow(900)
    replace_log([
        f"2026-05-02T11:00:00Z | DEBUG | latency=NaNms | invalid-{token}",
        f"2026-05-02T11:01:00Z | WARN | latency={lone}ms | lone-{secrets.token_hex(12)}",
        f"2026-05-02T11:02:00Z | ERROR | latency=-4ms | invalid-negative-{token}",
    ])
    request_and_assert_expected()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
