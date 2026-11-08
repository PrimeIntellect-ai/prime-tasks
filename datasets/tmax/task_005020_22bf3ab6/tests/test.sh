#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import sys
from pathlib import Path


def test_final_state():
    metrics_log = "/home/user/metrics.log"
    script_path = "/home/user/process_metrics.py"
    alerts_path = "/home/user/mail_spool/alerts.txt"
    actions_path = "/home/user/supervisor_actions.sh"

    assert os.path.isfile(metrics_log), f"{metrics_log} is missing."
    assert os.path.isfile(script_path), f"Required Python script {script_path} is missing."
    assert os.path.isfile(alerts_path), f"Output file {alerts_path} is missing."
    assert os.path.isfile(actions_path), f"Output file {actions_path} is missing."

    # Parse metrics.log to determine expected services exceeding quota
    exceeding_services = []
    with open(metrics_log, "r") as f:
        for line in f:
            match = re.search(r"SERVICE=(\S+)\s+USAGE=(\d+)\s+QUOTA=(\d+)", line)
            if match:
                service = match.group(1)
                usage = int(match.group(2))
                quota = int(match.group(3))
                if usage > quota:
                    exceeding_services.append((service, usage, quota))

    # Verify alerts.txt
    with open(alerts_path, "r") as f:
        alerts_content = f.read().strip()

    expected_alerts = []
    for service, usage, quota in exceeding_services:
        alert_block = (
            f"To: sre-alerts@company.local\n"
            f"Subject: Quota Exceeded for {service}\n"
            f"Body: Service {service} used {usage} bytes, exceeding quota of {quota} bytes."
        )
        expected_alerts.append(alert_block)

    expected_alerts_str = "\n\n".join(expected_alerts)

    # Normalize line endings and spacing for loose comparison
    norm_actual_alerts = re.sub(r'\n{3,}', '\n\n', alerts_content).strip()

    assert expected_alerts_str in norm_actual_alerts or norm_actual_alerts == expected_alerts_str, \
        f"Contents of {alerts_path} do not match the expected format and data.\nExpected:\n{expected_alerts_str}\n\nActual:\n{alerts_content}"

    # Verify supervisor_actions.sh
    with open(actions_path, "r") as f:
        actions_content = f.read().strip()

    expected_actions = [f"supervisorctl restart {service}" for service, _, _ in exceeding_services]
    expected_actions_str = "\n".join(expected_actions)

    assert actions_content == expected_actions_str, \
        f"Contents of {actions_path} do not match the expected commands.\nExpected:\n{expected_actions_str}\n\nActual:\n{actions_content}"

    # Exercise the submitted script against unpredictable metrics to ensure it
    # dynamically parses the input and appends correctly across executions.
    metrics_file = Path(metrics_log)
    alerts_file = Path(alerts_path)
    actions_file = Path(actions_path)
    original_metrics = metrics_file.read_bytes()
    original_alerts = alerts_file.read_bytes()
    original_actions = actions_file.read_bytes()

    token = secrets.token_hex(8)
    first_records = [
        (f"alpha_{token}", 91001, 91000),
        (f"beta_{token}", 42, 42),
        (f"gamma_{token}", 7, 900),
        (f"delta_{token}", 123456789, 123456788),
    ]
    second_records = [
        (f"epsilon_{token}", 500, 499),
        (f"zeta_{token}", 100, 101),
        (f"eta_{token}", 7000, 7000),
        (f"theta_{token}", 987654322, 987654321),
    ]

    def write_metrics(records, hour):
        lines = []
        for index, (service, usage, quota) in enumerate(records):
            lines.append(
                f"[2026-01-02 {hour:02d}:{index:02d}:00] "
                f"SERVICE={service} USAGE={usage} QUOTA={quota}"
            )
        metrics_file.write_text("\n".join(lines) + "\n")

    def expected_for(records):
        exceeding = [(s, u, q) for s, u, q in records if u > q]
        alerts = "\n\n".join(
            f"To: sre-alerts@company.local\n"
            f"Subject: Quota Exceeded for {service}\n"
            f"Body: Service {service} used {usage} bytes, exceeding quota of {quota} bytes."
            for service, usage, quota in exceeding
        )
        actions = "\n".join(
            f"supervisorctl restart {service}" for service, _, _ in exceeding
        )
        return alerts, actions

    try:
        alerts_file.unlink(missing_ok=True)
        actions_file.unlink(missing_ok=True)

        write_metrics(first_records, 10)
        subprocess.run(
            [sys.executable, script_path],
            cwd="/home/user",
            check=True,
            timeout=15,
        )
        assert alerts_file.is_file(), "Script did not create alerts.txt."
        assert actions_file.is_file(), "Script did not create supervisor_actions.sh."

        first_alerts, first_actions = expected_for(first_records)
        assert alerts_file.read_text().strip() == first_alerts
        assert actions_file.read_text().strip() == first_actions

        write_metrics(second_records, 11)
        subprocess.run(
            [sys.executable, script_path],
            cwd="/home/user",
            check=True,
            timeout=15,
        )

        second_alerts, second_actions = expected_for(second_records)
        combined_alerts = "\n\n".join([first_alerts, second_alerts])
        combined_actions = "\n".join([first_actions, second_actions])
        assert alerts_file.read_text().strip() == combined_alerts, \
            "Script did not append correctly formatted alerts for dynamic input."
        assert actions_file.read_text().strip() == combined_actions, \
            "Script did not append the expected restart commands for dynamic input."
    finally:
        metrics_file.write_bytes(original_metrics)
        alerts_file.parent.mkdir(parents=True, exist_ok=True)
        alerts_file.write_bytes(original_alerts)
        actions_file.write_bytes(original_actions)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
