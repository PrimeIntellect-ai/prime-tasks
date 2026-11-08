#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess

MONITOR_DIR = "/home/user/monitor"
DATA_DIR = os.path.join(MONITOR_DIR, "data")
SCRIPT_PATH = os.path.join(MONITOR_DIR, "uptime_monitor.sh")
CONFIG_PATH = os.path.join(MONITOR_DIR, "config.env")
LOG_PATH = os.path.join(DATA_DIR, "uptime.log")
REPORT_PATH = os.path.join(MONITOR_DIR, "report.txt")

EXPECTED_LINES = [
    "2023-10-01|99.9",
    "2023-10-02|100.0",
    "2023-10-03|99.5",
    "2023-10-04|98.2",
    "2023-10-06|99.1",
    "2023-10-07|100.0",
]


def run_monitor(timeout=5):
    if os.path.exists(REPORT_PATH):
        os.unlink(REPORT_PATH)
    try:
        return subprocess.run(
            [SCRIPT_PATH],
            cwd=MONITOR_DIR,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=timeout,
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        raise AssertionError("uptime_monitor.sh did not terminate; the retry loop still hangs") from exc


def test_uptime_log_cleaned():
    assert os.path.isfile(LOG_PATH), f"Log file {LOG_PATH} is missing."
    with open(LOG_PATH, "r") as f:
        lines = f.read().strip().splitlines()

    valid_format = re.compile(r"^\d{4}-\d{2}-\d{2}\|\d+(\.\d+)?$")
    for line in lines:
        if not line.strip():
            continue
        assert valid_format.match(line), f"Found malformed line in log: {line}"

    expected_dates = ["2023-10-01", "2023-10-02", "2023-10-03", "2023-10-04", "2023-10-06", "2023-10-07"]
    found_dates = [line.split("|")[0] for line in lines if line.strip()]
    for date in expected_dates:
        assert date in found_dates, f"Valid historical data for {date} is missing from the log."

    assert lines == EXPECTED_LINES, "The valid historical rows, values, order, or uniqueness were changed."


def test_config_env_secret_restored():
    assert os.path.isfile(CONFIG_PATH), f"Config file {CONFIG_PATH} is missing."
    with open(CONFIG_PATH, "r") as f:
        content = f.read()

    assert 'API_KEY="SRE_secret_8841a"' in content or "API_KEY='SRE_secret_8841a'" in content or "API_KEY=SRE_secret_8841a" in content, \
        "The correct API_KEY was not restored to config.env."

    loaded = subprocess.run(
        ["bash", "-c", 'source "$1"; printf "%s" "$API_KEY"', "bash", CONFIG_PATH],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=3,
        check=False,
    )
    assert loaded.returncode == 0 and loaded.stdout == "SRE_secret_8841a", \
        "config.env does not set API_KEY to the recovered value when sourced."


def test_uptime_script_bug_fixed():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} is missing."
    assert os.access(SCRIPT_PATH, os.X_OK), "uptime_monitor.sh is not executable."
    with open(SCRIPT_PATH, "r") as f:
        content = f.read()

    increment_patterns = [
        r"retries=\$\(\(retries\s*\+\s*1\)\)",
        r"let\s+retries\+\+",
        r"retries=\$\(expr\s+\$retries\s*\+\s*1\)",
        r"\(\(\s*retries\+\+\s*\)\)",
        r"retries=\$\[\s*retries\s*\+\s*1\s*\]",
    ]
    fixed = any(re.search(pattern, content) for pattern in increment_patterns)
    assert fixed, "The infinite loop bug in uptime_monitor.sh does not appear to be fixed (missing 'retries' increment)."


def test_script_behavior_on_derived_input():
    with open(LOG_PATH, "rb") as f:
        saved_log = f.read()
    with open(CONFIG_PATH, "rb") as f:
        saved_config = f.read()

    cents = 9200 + secrets.randbelow(600)
    values = [cents, cents + 3, cents + 6]
    probe_lines = [
        f"2041-01-01|{values[0] / 100:.2f}",
        f"2041-01-02|{values[1] / 100:.2f}",
        f"2041-01-03|{values[2] / 100:.2f}",
    ]
    expected_avg = f"{(cents + 3) / 100:.2f}"

    try:
        with open(CONFIG_PATH, "w") as f:
            f.write('API_KEY="SRE_secret_8841a"\nENDPOINT="https://api.monitoring.local/v1/status"\n')
        with open(LOG_PATH, "w") as f:
            f.write("\n".join(probe_lines) + "\n")

        result = run_monitor()
        assert result.returncode == 0, f"uptime_monitor.sh failed:\n{result.stdout}"
        assert result.stdout.count("Ping failed, retrying...") == 3, \
            "The simulated failed ping was not retried exactly three times."
        assert "Network unreachable after 3 attempts." in result.stdout
        assert os.path.isfile(REPORT_PATH), "The executed script did not generate report.txt."
        with open(REPORT_PATH, "r") as f:
            report = f.read()
        assert "API_STATUS=OK" in report
        assert f"Average Uptime={expected_avg}" in report, \
            "The executed script did not calculate the derived probe average."
    finally:
        with open(LOG_PATH, "wb") as f:
            f.write(saved_log)
        with open(CONFIG_PATH, "wb") as f:
            f.write(saved_config)
        if os.path.exists(REPORT_PATH):
            os.unlink(REPORT_PATH)


def test_report_generated_and_correct():
    result = run_monitor()
    assert result.returncode == 0, f"uptime_monitor.sh failed when executed:\n{result.stdout}"
    assert result.stdout.count("Ping failed, retrying...") == 3, \
        "The retry loop did not perform exactly three failed attempts."
    assert os.path.isfile(REPORT_PATH), f"Report file {REPORT_PATH} is missing. Did you run the script?"

    with open(REPORT_PATH, "r") as f:
        content = f.read()
    assert "API_STATUS=OK" in content, "The report does not contain API_STATUS=OK. The secret may be wrong or the script failed."

    with open(LOG_PATH, "r") as f:
        lines = [line for line in f.read().strip().splitlines() if line.strip()]
    total = 0.0
    count = 0
    for line in lines:
        parts = line.split("|")
        if len(parts) == 2:
            try:
                total += float(parts[1])
                count += 1
            except ValueError:
                pass
    expected_avg = round(total / count, 2) if count > 0 else 0.0
    expected_avg_str = f"{expected_avg:.2f}"
    assert f"Average Uptime={expected_avg_str}" in content, \
        f"The report does not contain the correct Average Uptime. Expected Average Uptime={expected_avg_str}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
