#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import configparser
import json
import os
import pwd
import re
import shlex
import signal
import subprocess
import tempfile
import time

import pytest

EXPECTED_HEALTH = {
    "status": "ok",
    "disk": "healthy",
    "processes": "healthy",
}


def read_json(path):
    try:
        with open(path, "r") as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"Output file {path} does not contain valid JSON")
    assert isinstance(data, dict), "JSON output should be a dictionary"
    return data


def run_once(binary_path, output_path, timeout=12):
    if os.path.exists(output_path):
        os.remove(output_path)
    start = time.perf_counter()
    result = subprocess.run(
        [binary_path, "--run-once"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=timeout,
    )
    duration = time.perf_counter() - start
    assert result.returncode == 0, (
        f"Binary {binary_path} failed with return code {result.returncode}"
    )
    assert os.path.isfile(output_path), (
        f"JSON output file {output_path} was not created by {binary_path}"
    )
    return duration, read_json(output_path)


def test_config_token_updated():
    config_path = "/home/user/monitor_config.ini"
    assert os.path.isfile(config_path), f"Config file missing at {config_path}"

    config = configparser.ConfigParser()
    try:
        config.read(config_path)
        with open(config_path, "r") as f:
            content = f.read()
            assert "824915" in content, (
                f"The correct authorization token '824915' was not found in {config_path}"
            )
        assert config.has_section("config"), "Missing [config] section"
        assert config.get("config", "auth_token", fallback="").strip() == "824915", (
            "The config auth_token is not the transcribed six-digit token"
        )
    except Exception as e:
        pytest.fail(f"Failed to read or parse {config_path}: {e}")


def test_optimized_binary_speedup_and_correctness():
    original_bin = "/home/user/bin/monitor.bak"
    optimized_bin = "/home/user/bin/monitor"
    source_path = "/home/user/src/monitor.c"
    json_output = "/home/user/health_status.json"

    assert os.path.isfile(original_bin), f"Original binary missing at {original_bin}"
    assert os.path.isfile(optimized_bin), f"Optimized binary missing at {optimized_bin}"
    assert os.access(optimized_bin, os.X_OK), (
        f"Optimized binary at {optimized_bin} is not executable"
    )
    assert os.path.isfile(source_path), f"Optimized source missing at {source_path}"
    assert os.path.getmtime(optimized_bin) >= os.path.getmtime(source_path), (
        "Deployed monitor predates monitor.c; compile and deploy the optimized source"
    )
    with open(optimized_bin, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Deployed monitor must be a compiled executable"

    # Retain the original timing comparison while also deriving the required output
    # from the shipped baseline implementation.
    new_time, new_data = run_once(optimized_bin, json_output)
    original_time, original_data = run_once(original_bin, json_output)

    assert original_data == EXPECTED_HEALTH, (
        "The baseline health-check output is not the expected reference format"
    )
    assert new_data == original_data, (
        "Optimized monitor did not emit the exact required health fields and values"
    )

    speedup = original_time / new_time if new_time > 0 else float("inf")
    assert speedup >= 5.0, (
        f"Execution speedup is {speedup:.2f}x, which is below the threshold of 5.0x "
        f"(Original: {original_time:.4f}s, Optimized: {new_time:.4f}s)"
    )

    # Compile the submitted monitor.c independently and exercise that artifact too,
    # ensuring the optimization and output logic are actually present in the source.
    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "monitor")
        compile_result = subprocess.run(
            ["gcc", source_path, "-o", rebuilt],
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert compile_result.returncode == 0, (
            f"monitor.c does not compile: {compile_result.stderr}"
        )
        rebuilt_time, rebuilt_data = run_once(rebuilt, json_output)
        assert rebuilt_data == original_data, (
            "A fresh build of monitor.c does not emit the required health JSON"
        )
        rebuilt_speedup = original_time / rebuilt_time if rebuilt_time > 0 else float("inf")
        assert rebuilt_speedup >= 5.0, (
            f"Freshly compiled monitor.c achieves only {rebuilt_speedup:.2f}x speedup"
        )


def test_systemd_service_active():
    unit_path = "/home/user/.config/systemd/user/health-monitor.service"
    optimized_bin = "/home/user/bin/monitor"
    json_output = "/home/user/health_status.json"

    assert os.path.isfile(unit_path), f"Service unit missing at {unit_path}"
    with open(unit_path, "r") as f:
        unit_text = f.read()
    exec_lines = re.findall(r"^\s*ExecStart\s*=\s*(.+?)\s*$", unit_text, re.MULTILINE)
    assert exec_lines, "health-monitor.service has no ExecStart"
    command = shlex.split(exec_lines[-1])
    assert command and command[0] == optimized_bin, (
        "health-monitor.service must start /home/user/bin/monitor"
    )

    # Preserve the original systemctl failed-state assertion where a user manager is
    # available, but do not mistake an unavailable manager for proof of success.
    try:
        subprocess.run(
            ["systemctl", "--user", "is-active", "health-monitor.service"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        result_failed = subprocess.run(
            ["systemctl", "--user", "is-failed", "health-monitor.service"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        assert result_failed.stdout.strip() != "failed", (
            "The health-monitor.service is in a failed state."
        )
    except Exception:
        pass

    # Actually start the configured daemon as the user-service account. It must stay
    # running and produce the required health document, rather than merely existing.
    account = pwd.getpwnam("user")

    def demote():
        os.initgroups(account.pw_name, account.pw_gid)
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    if os.path.exists(json_output):
        os.remove(json_output)
    proc = subprocess.Popen(
        command,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        cwd=account.pw_dir,
        preexec_fn=demote,
        start_new_session=True,
    )
    try:
        deadline = time.time() + 3
        while time.time() < deadline and not os.path.isfile(json_output):
            assert proc.poll() is None, (
                f"Service command exited immediately with code {proc.returncode}"
            )
            time.sleep(0.05)
        assert proc.poll() is None, "Service command did not remain running"
        assert os.path.isfile(json_output), "Started service did not create health_status.json"
        assert read_json(json_output) == EXPECTED_HEALTH, (
            "Started service produced incorrect health JSON"
        )
    finally:
        if proc.poll() is None:
            os.killpg(proc.pid, signal.SIGTERM)
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid, signal.SIGKILL)
                proc.wait(timeout=3)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
