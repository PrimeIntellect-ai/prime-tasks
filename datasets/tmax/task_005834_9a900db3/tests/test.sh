#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile
import pytest

EXECUTABLE = "/home/user/cost_monitor"
SOURCE = "/home/user/cost_monitor.cpp"
EXPECTED_DEFAULT = "[standard] Cost computation triggered."


def run_monitor(path, tier=None):
    env = os.environ.copy()
    if tier is None:
        env.pop("FINOPS_TIER", None)
        expected = EXPECTED_DEFAULT
    else:
        env["FINOPS_TIER"] = tier
        expected = f"[{tier}] Cost computation triggered."

    result = subprocess.run([path], env=env, capture_output=True, text=True)
    assert result.returncode == 0, f"Execution of {path} failed: {result.stderr}"
    assert result.stdout.strip() == expected, f"Unexpected output: {result.stdout.strip()}"


def test_cost_monitor_executable_exists():
    """Check that the compiled executable exists."""
    assert os.path.isfile(EXECUTABLE), "The executable /home/user/cost_monitor does not exist."
    assert os.access(EXECUTABLE, os.X_OK), "/home/user/cost_monitor is not executable."

    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/cost_monitor is not a compiled ELF executable."

    compiler_info = subprocess.run(
        ["readelf", "-p", ".comment", EXECUTABLE], capture_output=True, text=True
    )
    assert compiler_info.returncode == 0, "Could not inspect the compiled executable."
    assert "GCC:" in compiler_info.stdout, "The executable does not contain GCC compiler metadata."


def test_cost_monitor_execution_with_env():
    """Check the output of the C++ program when FINOPS_TIER is set."""
    env = os.environ.copy()
    env["FINOPS_TIER"] = "premium"
    result = subprocess.run([EXECUTABLE], env=env, capture_output=True, text=True)
    assert result.returncode == 0, "Execution of /home/user/cost_monitor failed."
    assert result.stdout.strip() == "[premium] Cost computation triggered.", f"Unexpected output: {result.stdout.strip()}"


def test_cost_monitor_execution_without_env():
    """Check the output of the C++ program when FINOPS_TIER is not set."""
    env = os.environ.copy()
    if "FINOPS_TIER" in env:
        del env["FINOPS_TIER"]
    result = subprocess.run([EXECUTABLE], env=env, capture_output=True, text=True)
    assert result.returncode == 0, "Execution of /home/user/cost_monitor failed."
    assert result.stdout.strip() == EXPECTED_DEFAULT, f"Unexpected output: {result.stdout.strip()}"


def test_cost_monitor_handles_arbitrary_tiers():
    """Exercise the submitted executable on verifier-generated tier values."""
    tiers = [
        "tier_" + secrets.token_hex(12),
        "ENTERPRISE_" + secrets.token_hex(9),
        secrets.token_urlsafe(18),
    ]
    for tier in tiers:
        run_monitor(EXECUTABLE, tier)


def test_cpp_source_and_gpp_build():
    """Validate the requested source and independently build and exercise it with g++."""
    assert os.path.isfile(SOURCE), "/home/user/cost_monitor.cpp does not exist."
    with open(SOURCE, "r", encoding="utf-8") as f:
        source = f.read()

    assert re.search(r"^\s*#\s*include\s*<iostream>", source, re.MULTILINE), "The source does not include <iostream>."
    assert re.search(r"^\s*#\s*include\s*<cstdlib>", source, re.MULTILINE), "The source does not include <cstdlib>."

    with tempfile.TemporaryDirectory() as tmpdir:
        rebuilt = os.path.join(tmpdir, "cost_monitor")
        build = subprocess.run(
            ["g++", SOURCE, "-o", rebuilt], capture_output=True, text=True
        )
        assert build.returncode == 0, f"g++ could not compile cost_monitor.cpp: {build.stderr}"
        assert build.stderr == "", f"g++ emitted warnings or errors: {build.stderr}"
        assert os.path.isfile(rebuilt) and os.access(rebuilt, os.X_OK)

        run_monitor(rebuilt, None)
        for tier in ["source_" + secrets.token_hex(10), secrets.token_urlsafe(16)]:
            run_monitor(rebuilt, tier)


def test_bashrc_configuration():
    """Check that .bashrc contains the correct environment variables."""
    assert os.path.isfile("/home/user/.bashrc"), "/home/user/.bashrc does not exist."
    with open("/home/user/.bashrc", "r") as f:
        content = f.read()

    tz_pattern = r'export\s+TZ=[\'\"]?Pacific/Auckland[\'\"]?'
    assert re.search(tz_pattern, content), ".bashrc does not correctly export TZ=Pacific/Auckland."

    tier_pattern = r'export\s+FINOPS_TIER=[\'\"]?enterprise[\'\"]?'
    assert re.search(tier_pattern, content), ".bashrc does not correctly export FINOPS_TIER=enterprise."


def test_cron_verification():
    """Check both the verification file and user's installed crontab."""
    assert os.path.isfile("/home/user/cron_verify.txt"), "/home/user/cron_verify.txt does not exist."
    with open("/home/user/cron_verify.txt", "r") as f:
        content = f.read()

    cron_pattern = r'^45\s+23\s+\*\s+\*\s+\*\s+/home/user/cost_monitor\b'
    found = False
    for line in content.splitlines():
        if re.search(cron_pattern, line.strip()):
            found = True
            break
    assert found, "cron_verify.txt does not contain the correct cron expression for /home/user/cost_monitor."

    installed = subprocess.run(
        ["crontab", "-u", "user", "-l"], capture_output=True, text=True
    )
    assert installed.returncode == 0, "The user account has no installed crontab."

    exact_pattern = r'^45\s+23\s+\*\s+\*\s+\*\s+/home/user/cost_monitor\s*$'
    assert any(re.fullmatch(exact_pattern, line.strip()) for line in installed.stdout.splitlines()), \
        "The user's installed crontab does not run /home/user/cost_monitor at exactly 23:45 daily."
    assert content == installed.stdout, "cron_verify.txt is not the output of the user's installed crontab."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
