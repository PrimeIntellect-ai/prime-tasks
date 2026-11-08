#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import shutil
import stat
import string
import subprocess
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

SERVICE_FILE = "/home/user/optimizer.service"
SCRIPT_FILE = "/home/user/cost_optimizer.py"
CONFIG_FILE = "/home/user/port_mapping.json"
OUTPUT_FILE = "/home/user/apply_port_rules.sh"
NY = ZoneInfo("America/New_York")
UTC = ZoneInfo("UTC")


def output_lines():
    assert os.path.isfile(OUTPUT_FILE), f"Output script {OUTPUT_FILE} was not created."
    with open(OUTPUT_FILE, "r") as f:
        return f.read().splitlines()


def assert_mode_700():
    perms = stat.S_IMODE(os.stat(OUTPUT_FILE).st_mode)
    assert perms == 0o700, f"Permissions for {OUTPUT_FILE} should be 700, but got {oct(perms)}."


def run_faketime_utc(utc_text, runtime_tz="UTC"):
    if os.path.exists(OUTPUT_FILE):
        os.remove(OUTPUT_FILE)
    env = os.environ.copy()
    env["TZ"] = "UTC"
    return subprocess.run(
        ["faketime", utc_text, "env", f"TZ={runtime_tz}", "python3", SCRIPT_FILE],
        env=env,
        capture_output=True,
        text=True,
        timeout=10,
    )


def run_at_new_york_time(year, month, day, hour, minute, runtime_tz="UTC"):
    local_time = datetime(year, month, day, hour, minute, 0, tzinfo=NY)
    utc_text = local_time.astimezone(UTC).strftime("%Y-%m-%d %H:%M:%S")
    return run_faketime_utc(utc_text, runtime_tz)


def expected_commands(mapping):
    return [
        f"socat TCP4-LISTEN:{ports['listen']},bind=127.0.0.1,fork TCP4:127.0.0.1:{ports['target']} &"
        for ports in mapping.values()
    ]


def test_systemd_service_configured():
    assert os.path.isfile(SERVICE_FILE), f"Service file {SERVICE_FILE} is missing."
    with open(SERVICE_FILE, "r") as f:
        content = f.read()

    assert re.search(r"^After=.*billing-api\.service", content, re.MULTILINE), \
        "optimizer.service does not contain the correct 'After=billing-api.service' directive."

    assert re.search(r"^ExecStart=.*python3\s+/home/user/cost_optimizer\.py", content, re.MULTILINE), \
        "optimizer.service does not contain the correct 'ExecStart' directive calling cost_optimizer.py with python3."


def test_python_script_exists():
    assert os.path.isfile(SCRIPT_FILE), f"Python script {SCRIPT_FILE} is missing."


def test_execution_business_hours_original_case():
    mapping = {
        "db": {"listen": 5432, "target": 15432},
        "cache": {"listen": 6379, "target": 16379},
    }
    with open(CONFIG_FILE, "w") as f:
        json.dump(mapping, f)

    # 2023-10-10 16:00:00 UTC is 12:00 PM EDT in New York.
    result = run_faketime_utc("2023-10-10 16:00:00")
    assert result.returncode == 0, f"Script failed during business hours execution: {result.stderr}"
    lines = output_lines()

    assert "socat TCP4-LISTEN:5432,bind=127.0.0.1,fork TCP4:127.0.0.1:15432 &" in lines, \
        "Missing or incorrect socat command for 'db' during business hours."
    assert "socat TCP4-LISTEN:6379,bind=127.0.0.1,fork TCP4:127.0.0.1:16379 &" in lines, \
        "Missing or incorrect socat command for 'cache' during business hours."
    assert sorted(lines) == sorted(expected_commands(mapping)), \
        "Business-hours output must contain exactly one correctly formatted command per configured service."
    assert_mode_700()


def test_execution_off_hours_original_case():
    # 2023-10-10 04:00:00 UTC is midnight EDT in New York.
    result = run_faketime_utc("2023-10-10 04:00:00")
    assert result.returncode == 0, f"Script failed during off-hours execution: {result.stderr}"
    lines = output_lines()
    assert 'echo "Off-hours: tunnels disabled"' in lines, \
        "Output script does not contain the correct off-hours message."
    assert lines == ['echo "Off-hours: tunnels disabled"'], \
        "Off-hours output must contain exactly the required line."
    assert_mode_700()


def test_random_mapping_boundaries_dst_and_default_timezone():
    rng = random.SystemRandom()
    mapping = {}
    used_ports = set()
    for index in range(rng.randint(3, 6)):
        name = "svc_" + "".join(rng.choice(string.ascii_letters) for _ in range(10)) + str(index)
        while True:
            listen = rng.randint(2000, 60000)
            target = rng.randint(2000, 60000)
            if listen not in used_ports and target not in used_ports and listen != target:
                used_ports.update((listen, target))
                break
        mapping[name] = {"listen": listen, "target": target}

    with open(CONFIG_FILE, "w") as f:
        json.dump(mapping, f)

    expected = expected_commands(mapping)
    # Exercise both standard and daylight time, both inclusive boundaries, and
    # the adjacent excluded minutes. The child process deliberately uses
    # non-New-York default timezones in several cases.
    cases = [
        (2027, 1, 19, 8, 59, False, "Asia/Tokyo"),
        (2027, 1, 19, 9, 0, True, "Europe/London"),
        (2027, 1, 19, 17, 59, True, "UTC"),
        (2027, 1, 19, 18, 0, False, "Asia/Tokyo"),
        (2028, 7, 11, 8, 59, False, "Europe/London"),
        (2028, 7, 11, 9, 0, True, "Asia/Tokyo"),
        (2028, 7, 11, 17, 59, True, "Europe/London"),
        (2028, 7, 11, 18, 0, False, "UTC"),
    ]

    # Add an unpredictable date and business-hour minute so fixed timestamp
    # special-casing cannot satisfy the verifier.
    year = rng.randint(2024, 2034)
    month = rng.randint(1, 12)
    day = rng.randint(1, 25)
    hour = rng.randint(9, 17)
    minute = rng.randint(0, 59)
    cases.append((year, month, day, hour, minute, True, rng.choice(["UTC", "Asia/Tokyo", "Europe/London"])))

    for year, month, day, hour, minute, is_business, runtime_tz in cases:
        result = run_at_new_york_time(year, month, day, hour, minute, runtime_tz)
        assert result.returncode == 0, \
            f"Script failed for New York time {year}-{month:02}-{day:02} {hour:02}:{minute:02}: {result.stderr}"
        lines = output_lines()
        if is_business:
            assert sorted(lines) == sorted(expected), \
                f"Incorrect exact business-hours output at {hour:02}:{minute:02} New York time."
        else:
            assert lines == ['echo "Off-hours: tunnels disabled"'], \
                f"Incorrect exact off-hours output at {hour:02}:{minute:02} New York time."
        assert_mode_700()


def test_execution_invalid_json():
    for malformed in ('{"service": ', 'this is not json', '[1, 2,'):
        Path(CONFIG_FILE).write_text(malformed)
        if os.path.exists(OUTPUT_FILE):
            os.remove(OUTPUT_FILE)
        result = subprocess.run(
            ["python3", SCRIPT_FILE], capture_output=True, text=True, timeout=10
        )
        assert os.path.isfile(OUTPUT_FILE), \
            f"Output script {OUTPUT_FILE} was not created for invalid JSON. stderr: {result.stderr}"
        assert output_lines() == ['echo "Error: missing config"'], \
            "Invalid JSON must produce exactly the required error line."
        assert_mode_700()


def test_execution_missing_config():
    backup_file = f"{CONFIG_FILE}.bak"
    if os.path.exists(backup_file):
        os.remove(backup_file)
    if os.path.exists(CONFIG_FILE):
        shutil.move(CONFIG_FILE, backup_file)

    try:
        if os.path.exists(OUTPUT_FILE):
            os.remove(OUTPUT_FILE)

        result = subprocess.run(
            ["python3", SCRIPT_FILE],
            capture_output=True,
            text=True,
            timeout=10,
        )
        assert os.path.isfile(OUTPUT_FILE), \
            f"Output script {OUTPUT_FILE} was not created when config is missing."
        lines = output_lines()
        assert 'echo "Error: missing config"' in lines, \
            "Output script does not contain the correct error message when config is missing."
        assert lines == ['echo "Error: missing config"'], \
            "Missing config must produce exactly the required error line."
        assert_mode_700()
    finally:
        if os.path.exists(backup_file):
            shutil.move(backup_file, CONFIG_FILE)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
