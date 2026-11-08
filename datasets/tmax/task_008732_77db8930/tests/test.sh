#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import stat
import subprocess
from datetime import datetime, timedelta, timezone

import pytest

HOME = "/home/user"
LOG_PATH = f"{HOME}/logs/services.log"
CONFIG_PATH = f"{HOME}/config/service_groups.conf"
ALERTS_PATH = f"{HOME}/alerts.json"
SCRIPT_PATH = f"{HOME}/run_monitor.sh"
SOURCE_PATH = f"{HOME}/monitor.go"
BIN_PATH = f"{HOME}/monitor_bin"

EXPECTED_ORIGINAL = [
    {"timestamp": "2023-10-25T21:30:00Z", "service": "auth-service", "group": "sec-ops"},
    {"timestamp": "2023-10-26T00:00:00Z", "service": "payment-service", "group": "fin-ops"},
    {"timestamp": "2023-10-26T01:20:00Z", "service": "unknown-service", "group": "unknown"},
]


def read_alerts():
    assert os.path.isfile(ALERTS_PATH), f"{ALERTS_PATH} is missing. Did the program run successfully?"
    with open(ALERTS_PATH, "r", encoding="utf-8") as f:
        try:
            alerts = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{ALERTS_PATH} does not contain valid JSON")
    assert isinstance(alerts, list), f"Expected alerts to be a JSON array, got {type(alerts).__name__}"
    return alerts


def assert_alerts(expected):
    alerts = read_alerts()
    assert len(alerts) == len(expected), f"Expected {len(expected)} alerts, but found {len(alerts)}"
    for i, (actual, wanted) in enumerate(zip(alerts, expected)):
        assert actual == wanted, f"Alert at index {i} does not match expected output.\nExpected: {wanted}\nActual: {actual}"


def write_original_inputs():
    with open(LOG_PATH, "w", encoding="utf-8") as f:
        f.write("""[2023-10-25 10:15:00 UTC] db-service OK All checks passed
[2023-10-25 14:30:00 PDT] auth-service ERROR Connection Refused to backend
[2023-10-25 17:45:00 EST] cache-service WARN High memory usage
[2023-10-26 09:00:00 JST] payment-service ERROR Connection Refused from gateway
[2023-10-26 01:20:00 UTC] unknown-service ERROR Connection Refused on port 8080
[2023-10-26 08:30:00 PDT] auth-service ERROR Invalid Credentials
""")
    with open(CONFIG_PATH, "w", encoding="utf-8") as f:
        f.write("""db-service:db-admins
auth-service:sec-ops
cache-service:core-eng
payment-service:fin-ops
""")


def make_random_fixture():
    token = secrets.token_hex(6)
    known = [f"svc-a-{token}", f"svc-b-{token}", f"svc-c-{token}"]
    unknown = f"svc-unknown-{token}"
    groups = {
        known[0]: f"group-a-{token}",
        known[1]: f"group-b-{token}",
        known[2]: f"group-c-{token}",
    }
    offsets = {"UTC": 0, "PDT": -7, "EST": -5, "JST": 9}

    def random_stamp():
        raw = secrets.randbelow
        return (2021 + raw(5), 1 + raw(12), 1 + raw(20), raw(24), raw(60), raw(60))

    records = [
        (random_stamp(), "UTC", known[0], "OK", "Connection Refused but status is OK"),
        (random_stamp(), "PDT", known[0], "ERROR", "Connection Refused to randomized backend"),
        (random_stamp(), "EST", known[1], "WARN", "Connection Refused but status is WARN"),
        (random_stamp(), "JST", unknown, "ERROR", "Connection Refused"),
        (random_stamp(), "EST", known[1], "ERROR", "Connection Refused from randomized peer"),
        (random_stamp(), "UTC", known[2], "ERROR", "connection Refused wrong capitalization"),
        (random_stamp(), "PDT", known[2], "ERROR", "XConnection Refused not at message start"),
        (random_stamp(), "UTC", known[2], "ERROR", "Connection Refused on randomized port"),
    ]

    expected = []
    lines = []
    for parts, zone, service, status, message in records:
        year, month, day, hour, minute, second = parts
        lines.append(
            f"[{year:04d}-{month:02d}-{day:02d} {hour:02d}:{minute:02d}:{second:02d} {zone}] "
            f"{service} {status} {message}"
        )
        if status == "ERROR" and message.startswith("Connection Refused"):
            local = datetime(year, month, day, hour, minute, second,
                             tzinfo=timezone(timedelta(hours=offsets[zone])))
            expected.append({
                "timestamp": local.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                "service": service,
                "group": groups.get(service, "unknown"),
            })

    with open(LOG_PATH, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    with open(CONFIG_PATH, "w", encoding="utf-8") as f:
        for service, group in groups.items():
            f.write(f"{service}:{group}\n")
    return expected


def run_checked(command, timeout=60):
    result = subprocess.run(
        command,
        cwd=HOME,
        env=os.environ.copy(),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )
    assert result.returncode == 0, (
        f"Command failed ({result.returncode}): {' '.join(command)}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_monitor_go_exists():
    assert os.path.isfile(SOURCE_PATH), f"{SOURCE_PATH} is missing"


def test_run_monitor_sh_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is missing"
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"{SCRIPT_PATH} is not executable"


def test_monitor_bin_exists():
    assert os.path.isfile(BIN_PATH), f"{BIN_PATH} is missing. Did the script compile the Go program?"


def test_alerts_json_content():
    assert_alerts(EXPECTED_ORIGINAL)


def test_run_monitor_executes_on_original_fixture():
    write_original_inputs()
    if os.path.exists(ALERTS_PATH):
        os.remove(ALERTS_PATH)
    run_checked([SCRIPT_PATH])
    assert os.path.isfile(BIN_PATH), "run_monitor.sh did not create /home/user/monitor_bin"
    assert bool(os.stat(BIN_PATH).st_mode & stat.S_IXUSR), "monitor_bin is not executable"
    with open(BIN_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "monitor_bin is not a compiled executable"
    assert_alerts(EXPECTED_ORIGINAL)


def test_script_sets_required_timezone_and_handles_unseen_inputs():
    with open(SCRIPT_PATH, "r", encoding="utf-8") as f:
        script = f.read()
    normalized = script.replace("'", "").replace('"', "")
    assert re.search(
        r"(?m)(?:^|[;\s])(?:export\s+)?TZ\s*=\s*Europe/London(?:\s|;|$)",
        normalized,
    ), "run_monitor.sh does not set TZ=Europe/London"

    expected = make_random_fixture()
    for path in (ALERTS_PATH, BIN_PATH):
        if os.path.exists(path):
            os.remove(path)
    run_checked([SCRIPT_PATH])
    assert os.path.isfile(BIN_PATH), "run_monitor.sh did not recreate monitor_bin"
    assert bool(os.stat(BIN_PATH).st_mode & stat.S_IXUSR), "recreated monitor_bin is not executable"
    with open(BIN_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "run_monitor.sh did not produce a compiled executable"
    assert_alerts(expected)


def test_monitor_go_builds_and_compiled_program_handles_unseen_inputs():
    verifier_bin = "/tmp/verifier_monitor_bin"
    if os.path.exists(verifier_bin):
        os.remove(verifier_bin)
    run_checked(["go", "build", "-o", verifier_bin, SOURCE_PATH])
    assert os.path.isfile(verifier_bin), "monitor.go did not compile into an executable"

    expected = make_random_fixture()
    if os.path.exists(ALERTS_PATH):
        os.remove(ALERTS_PATH)
    run_checked([verifier_bin])
    assert_alerts(expected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
