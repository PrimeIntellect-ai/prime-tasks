#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import uuid
from pathlib import Path

import pytest

EXE_PATH = Path("/home/user/finops_monitor")
SOURCE_PATH = Path("/home/user/finops_monitor.c")
CONFIG_PATH = Path("/home/user/cloud_fstab")
LOG_PATH = Path("/home/user/cost_alerts.log")


def test_executable_exists_and_is_executable():
    assert EXE_PATH.is_file(), f"Compiled executable {EXE_PATH} does not exist."
    assert os.access(EXE_PATH, os.X_OK), f"File {EXE_PATH} is not executable."
    assert EXE_PATH.read_bytes()[:4] == b"\x7fELF", f"{EXE_PATH} is not a compiled ELF executable."


def test_cost_alerts_log_content():
    assert LOG_PATH.is_file(), f"Log file {LOG_PATH} was not created."

    content = LOG_PATH.read_text().strip()
    expected_lines = [
        "ALERT: volume vol_db_main exceeds 100",
        "ALERT: volume vol_analytics exceeds 100",
    ]
    actual_lines = [line.strip() for line in content.splitlines() if line.strip()]

    assert len(actual_lines) == 2, f"Expected exactly 2 alert lines, found {len(actual_lines)}."
    for expected in expected_lines:
        assert expected in actual_lines, f"Missing expected log entry: '{expected}'"


def test_cloud_fstab_was_not_modified():
    expected = (
        b"# Cloud Storage Volumes\n"
        b"vol_app_data 45\n"
        b"vol_db_main 150\n"
        b"\n"
        b"vol_backups 20\n"
        b"vol_analytics 105\n"
    )
    assert CONFIG_PATH.read_bytes() == expected, "/home/user/cloud_fstab was modified."


def test_crontab_entry_exists():
    try:
        result = subprocess.run(
            ["crontab", "-u", "user", "-l"], capture_output=True, text=True
        )
        if result.returncode != 0:
            result = subprocess.run(
                ["crontab", "-l"], capture_output=True, text=True
            )
    except Exception as exc:
        pytest.fail(f"Failed to execute crontab command: {exc}")

    assert result.returncode == 0, "Failed to retrieve crontab. Is it installed?"
    pattern = r"\*/5\s+\*\s+\*\s+\*\s+\*\s+/home/user/finops_monitor"
    assert re.search(pattern, result.stdout) is not None, (
        "Crontab entry for /home/user/finops_monitor running every 5 minutes was not found."
    )


def test_installed_binary_and_repaired_source_on_derived_input():
    assert SOURCE_PATH.is_file(), f"Source file {SOURCE_PATH} does not exist."

    token = uuid.uuid4().hex
    low = f"vol_low_{token}"
    equal = f"vol_equal_{token}"
    high1 = f"vol_high_a_{token}"
    high2 = f"vol_high_b_{token}"
    generated_config = (
        f"# generated comment {token}\n"
        "\n"
        "   \t\n"
        f"{low} 99\n"
        f"{equal} 100\n"
        f"{high1} 101\n"
        "# another comment\n"
        "malformed_line_without_cost\n"
        f"{high2} 237\n"
    ).encode()
    expected = [
        f"ALERT: volume {high1} exceeds 100",
        f"ALERT: volume {high2} exceeds 100",
    ]

    original_config = CONFIG_PATH.read_bytes()
    original_log = LOG_PATH.read_bytes()
    rebuilt = Path(f"/tmp/finops_monitor_from_source_{token}")

    try:
        compile_result = subprocess.run(
            ["gcc", str(SOURCE_PATH), "-o", str(rebuilt)],
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert compile_result.returncode == 0, (
            "The repaired C source does not compile with gcc:\n" + compile_result.stderr
        )
        assert rebuilt.read_bytes()[:4] == b"\x7fELF"
        rebuilt.chmod(0o755)

        for artifact in (EXE_PATH, rebuilt):
            CONFIG_PATH.write_bytes(generated_config)
            if LOG_PATH.exists():
                LOG_PATH.unlink()

            result = subprocess.run(
                ["runuser", "-u", "user", "--", str(artifact)],
                capture_output=True,
                text=True,
                timeout=10,
            )
            assert result.returncode == 0, (
                f"{artifact} failed on comments/empty lines with exit code "
                f"{result.returncode}: {result.stderr}"
            )
            assert LOG_PATH.is_file(), f"{artifact} did not create {LOG_PATH}."
            actual = [
                line.strip()
                for line in LOG_PATH.read_text().splitlines()
                if line.strip()
            ]
            assert actual == expected, (
                f"{artifact} produced incorrect alerts for verifier-derived input. "
                f"Expected {expected}, got {actual}."
            )
    finally:
        CONFIG_PATH.write_bytes(original_config)
        LOG_PATH.write_bytes(original_log)
        if rebuilt.exists():
            rebuilt.unlink()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
