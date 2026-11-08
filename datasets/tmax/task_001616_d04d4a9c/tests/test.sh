#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import secrets
import shutil
import stat
import subprocess
from datetime import datetime, timedelta

import pytest

RAW_PATH = "/home/user/input/raw_sensor.csv"
TEMPLATE_PATH = "/home/user/input/report_template.txt"
REPORT_PATH = "/home/user/output/report.txt"
PROCESSOR_PATH = "/home/user/process_sensor.py"
WRAPPER_PATH = "/home/user/run_pipeline.sh"

ORIGINAL_RAW = """timestamp,temperature,humidity
2023-10-01T10:00:00,22.5,45.0
2023-10-01T10:05:00,,46.0
2023-10-01T10:10:00,23.5,
2023-10-01T10:15:00,24.0,48.0
"""

ORIGINAL_TEMPLATE = """Daily Sensor Report
-------------------
Temperature: Min {{TEMP_MIN}}, Max {{TEMP_MAX}}, Avg {{TEMP_AVG}}
Humidity: Min {{HUM_MIN}}, Max {{HUM_MAX}}, Avg {{HUM_AVG}}
"""


def run_as_user(command):
    return subprocess.run(
        ["runuser", "-u", "user", "--"] + command,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )


def test_report_file_exists_and_content_correct():
    assert os.path.exists(REPORT_PATH), f"Report file was not created at {REPORT_PATH}"

    with open(REPORT_PATH, "r") as f:
        report_content = f.read()

    expected_temp_line = "Temperature: Min 22.50, Max 24.00, Avg 23.25"
    expected_hum_line = "Humidity: Min 45.00, Max 48.00, Avg 46.50"

    assert expected_temp_line in report_content, (
        f"Temperature metrics incorrect or not formatted properly in {REPORT_PATH}. "
        f"Expected to find: '{expected_temp_line}'"
    )
    assert expected_hum_line in report_content, (
        f"Humidity metrics incorrect or not formatted properly in {REPORT_PATH}. "
        f"Expected to find: '{expected_hum_line}'"
    )


def test_pipeline_script_exists_and_executable():
    assert os.path.exists(WRAPPER_PATH), f"Wrapper script not found at {WRAPPER_PATH}"
    assert os.path.isfile(WRAPPER_PATH), f"Wrapper path is not a regular file: {WRAPPER_PATH}"
    assert os.access(WRAPPER_PATH, os.X_OK), f"Wrapper script at {WRAPPER_PATH} is not executable"


def test_python_script_exists():
    assert os.path.exists(PROCESSOR_PATH), f"Python script not found at {PROCESSOR_PATH}"
    assert os.path.isfile(PROCESSOR_PATH), f"Python script is not a regular file: {PROCESSOR_PATH}"


def test_required_input_files_have_exact_sample_content():
    with open(RAW_PATH, "r") as f:
        assert f.read() == ORIGINAL_RAW
    with open(TEMPLATE_PATH, "r") as f:
        assert f.read() == ORIGINAL_TEMPLATE


def test_crontab_configured_for_user_account():
    try:
        crontab_out = subprocess.check_output(
            ["crontab", "-u", "user", "-l"], stderr=subprocess.STDOUT
        ).decode("utf-8")
    except subprocess.CalledProcessError:
        pytest.fail("Crontab was not configured for the user account")

    valid_schedules = ["*/15 * * * *", "0,15,30,45 * * * *"]
    schedule_found = any(sched in crontab_out for sched in valid_schedules)
    assert schedule_found, (
        "Crontab not scheduled for every 15 mins. Expected "
        "'*/15 * * * *' or '0,15,30,45 * * * *'"
    )
    assert WRAPPER_PATH in crontab_out, (
        "Crontab does not execute the wrapper script /home/user/run_pipeline.sh"
    )

    active_match = False
    for line in crontab_out.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if re.match(r"^(?:\*/15|0,15,30,45)\s+\*\s+\*\s+\*\s+\*\s+.*(?:^|\s)/home/user/run_pipeline\.sh(?:\s|$)", line):
            active_match = True
            break
    assert active_match, "No active every-15-minutes cron entry runs the required wrapper"


def interpolate(times, values):
    result = list(values)
    for i, value in enumerate(result):
        if value is not None:
            continue
        left = i - 1
        while result[left] is None:
            left -= 1
        right = i + 1
        while result[right] is None:
            right += 1
        elapsed = (times[i] - times[left]).total_seconds()
        span = (times[right] - times[left]).total_seconds()
        result[i] = result[left] + (result[right] - result[left]) * elapsed / span
    return result


def expected_report(template, temperatures, humidities):
    replacements = {
        "{{TEMP_MIN}}": f"{min(temperatures):.2f}",
        "{{TEMP_MAX}}": f"{max(temperatures):.2f}",
        "{{TEMP_AVG}}": f"{sum(temperatures) / len(temperatures):.2f}",
        "{{HUM_MIN}}": f"{min(humidities):.2f}",
        "{{HUM_MAX}}": f"{max(humidities):.2f}",
        "{{HUM_AVG}}": f"{sum(humidities) / len(humidities):.2f}",
    }
    for placeholder, value in replacements.items():
        template = template.replace(placeholder, value)
    return template


def test_processor_and_wrapper_on_unseen_irregular_data():
    processor_bytes = open(PROCESSOR_PATH, "rb").read()
    processor_mode = stat.S_IMODE(os.stat(PROCESSOR_PATH).st_mode)
    nonce = secrets.token_hex(8)

    increments = [0, 2, 9, 13, 24, 31, 47]
    base = datetime(2025, 2, 3, 6, 0, 0)
    times = [base + timedelta(minutes=m) for m in increments]

    offset = secrets.randbelow(80) / 10.0
    temperatures = [11.3 + offset, None, 28.7 + offset, None, None, 17.9 + offset, 35.1 + offset]
    humidities = [61.2 + offset, 48.4 + offset, None, None, 73.8 + offset, None, 52.6 + offset]

    complete_temps = interpolate(times, temperatures)
    complete_hums = interpolate(times, humidities)

    dynamic_template = (
        f"Verification report {nonce}\n"
        "Temperature: Min {{TEMP_MIN}}, Max {{TEMP_MAX}}, Avg {{TEMP_AVG}}\n"
        "Humidity: Min {{HUM_MIN}}, Max {{HUM_MAX}}, Avg {{HUM_AVG}}\n"
        f"End token {nonce}\n"
    )
    wanted = expected_report(dynamic_template, complete_temps, complete_hums)

    try:
        os.makedirs("/home/user/input", exist_ok=True)
        os.chmod("/home/user/input", 0o777)
        with open(RAW_PATH, "w", newline="") as f:
            writer = csv.writer(f, lineterminator="\n")
            writer.writerow(["timestamp", "temperature", "humidity"])
            for timestamp, temp, hum in zip(times, temperatures, humidities):
                writer.writerow([
                    timestamp.isoformat(),
                    "" if temp is None else str(temp),
                    "" if hum is None else str(hum),
                ])
        with open(TEMPLATE_PATH, "w") as f:
            f.write(dynamic_template)
        os.chmod(RAW_PATH, 0o644)
        os.chmod(TEMPLATE_PATH, 0o644)

        os.makedirs("/home/user/output", exist_ok=True)
        os.chmod("/home/user/output", 0o777)
        if os.path.exists(REPORT_PATH):
            os.remove(REPORT_PATH)

        # Execute the requested Python artifact itself on data not known in advance.
        run_as_user(["python3", PROCESSOR_PATH])
        with open(REPORT_PATH, "r") as f:
            assert f.read() == wanted

        # Execute the real wrapper with the real processor and require it to recreate output/.
        shutil.rmtree("/home/user/output")
        run_as_user([WRAPPER_PATH])
        assert os.path.isdir("/home/user/output"), "Wrapper did not create the output directory"
        with open(REPORT_PATH, "r") as f:
            assert f.read() == wanted

        # Ensure the wrapper actually invokes /home/user/process_sensor.py rather than
        # independently hardcoding the report behavior.
        marker = f"/tmp/process_sensor_invoked_{nonce}"
        sentinel = (
            "#!/usr/bin/env python3\n"
            "import os\n"
            "assert os.path.isdir('/home/user/output')\n"
            f"open({marker!r}, 'w').write('invoked')\n"
        ).encode()
        with open(PROCESSOR_PATH, "wb") as f:
            f.write(sentinel)
        os.chmod(PROCESSOR_PATH, 0o755)
        if os.path.exists(marker):
            os.remove(marker)
        shutil.rmtree("/home/user/output")
        run_as_user([WRAPPER_PATH])
        assert os.path.exists(marker), "Wrapper did not execute /home/user/process_sensor.py"
    finally:
        with open(PROCESSOR_PATH, "wb") as f:
            f.write(processor_bytes)
        os.chmod(PROCESSOR_PATH, processor_mode)
        os.makedirs("/home/user/input", exist_ok=True)
        os.makedirs("/home/user/output", exist_ok=True)
        os.chmod("/home/user/input", 0o777)
        os.chmod("/home/user/output", 0o777)
        with open(RAW_PATH, "w") as f:
            f.write(ORIGINAL_RAW)
        with open(TEMPLATE_PATH, "w") as f:
            f.write(ORIGINAL_TEMPLATE)
        os.chmod(RAW_PATH, 0o644)
        os.chmod(TEMPLATE_PATH, 0o644)
        try:
            run_as_user([WRAPPER_PATH])
        except Exception:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
