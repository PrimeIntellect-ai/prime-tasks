#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import configparser
import glob
import os
import re
import secrets
import stat
import subprocess


def test_environment_hardening():
    bashrc_path = "/home/user/.bashrc"
    assert os.path.isfile(bashrc_path), f"{bashrc_path} does not exist."

    with open(bashrc_path, "r") as f:
        content = f.read()

    # Allow either export APP_SECURE_MODE=strict or just APP_SECURE_MODE=strict
    assert re.search(r"(?:export\s+)?APP_SECURE_MODE=strict", content), \
        f"APP_SECURE_MODE=strict not found in {bashrc_path}."


def test_app_config_ini():
    config_path = "/home/user/app_config.ini"
    assert os.path.isfile(config_path), f"{config_path} does not exist."

    config = configparser.ConfigParser()
    config.read(config_path)

    assert "security" in config, "Missing [security] section in app_config.ini."
    assert config["security"].get("tls_enabled") == "true", "tls_enabled must be true in [security] section."
    assert config["security"].get("max_connections") == "50", "max_connections must be 50 in [security] section."

    assert "logging" in config, "Missing [logging] section in app_config.ini."
    assert config["logging"].get("path") == "/home/user/app_logs/service.log", \
        "path must be /home/user/app_logs/service.log in [logging] section."


def test_logrotate_conf():
    logrotate_path = "/home/user/logrotate.conf"
    log_dir = "/home/user/app_logs"
    log_file = os.path.join(log_dir, "service.log")

    assert os.path.isdir(log_dir), f"{log_dir} was not created by the agent."
    assert os.path.isfile(logrotate_path), f"{logrotate_path} does not exist."

    with open(logrotate_path, "r") as f:
        content = f.read()

    assert "/home/user/app_logs/service.log" in content, "logrotate.conf does not target /home/user/app_logs/service.log."
    assert "daily" in content, "logrotate.conf is missing 'daily' directive."
    assert "rotate 7" in content, "logrotate.conf is missing 'rotate 7' directive."
    assert "compress" in content, "logrotate.conf is missing 'compress' directive."
    assert re.search(r"create\s+(0)?600", content), "logrotate.conf is missing 'create 0600' directive."

    # Have logrotate parse the configuration, and use its parsed description to
    # ensure the target stanza really has daily scheduling and seven rotations.
    debug_state = f"/tmp/logrotate-debug-{os.getpid()}.state"
    debug = subprocess.run(
        ["logrotate", "-d", "-s", debug_state, logrotate_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=10,
    )
    assert debug.returncode == 0, f"logrotate rejected the configuration:\n{debug.stdout}"
    parsed_stanza = re.compile(
        r"rotating pattern:\s*/home/user/app_logs/service\.log\s+"
        r"after\s+1\s+days?\s+\(7 rotations\)",
        re.MULTILINE,
    )
    assert parsed_stanza.search(debug.stdout), \
        f"The parsed target stanza is not daily with exactly 7 rotations:\n{debug.stdout}"

    # Exercise a real forced rotation to verify compression and creation mode.
    for path in glob.glob(log_file + "*"):
        if os.path.isfile(path) or os.path.islink(path):
            os.remove(path)
    with open(log_file, "w") as f:
        f.write("rotation-test-" + secrets.token_hex(24) + "\n")

    state_path = f"/tmp/logrotate-state-{os.getpid()}"
    result = subprocess.run(
        ["logrotate", "-f", "-v", "-s", state_path, logrotate_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, f"logrotate could not execute the configuration:\n{result.stdout}"
    assert os.path.isfile(log_file), "logrotate did not create a new service.log."
    assert stat.S_IMODE(os.stat(log_file).st_mode) == 0o600, \
        "The newly created service.log does not have 0600 permissions."

    archives = [p for p in glob.glob(log_file + "*") if p != log_file and os.path.isfile(p)]
    assert archives, "logrotate did not create a rotated copy of service.log."
    compressed = []
    for path in archives:
        with open(path, "rb") as f:
            if f.read(2) == b"\x1f\x8b":
                compressed.append(path)
    assert compressed, "The rotated service log was not compressed."


def _run_monitor(script_path, health_file):
    result = subprocess.run([script_path], check=False, timeout=10)
    assert result.returncode == 0, f"Monitor exited with status {result.returncode}."
    assert os.path.isfile(health_file), f"{health_file} was not created by the script."
    with open(health_file, "r") as f:
        return f.read().strip()


def test_health_check_script():
    script_path = "/home/user/monitor.sh"
    log_dir = "/home/user/app_logs"
    log_file = os.path.join(log_dir, "service.log")
    health_file = "/home/user/health.txt"

    assert os.path.isfile(script_path), f"{script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable."

    os.makedirs(log_dir, exist_ok=True)

    # Test 1: Log file does not exist
    if os.path.exists(log_file):
        os.remove(log_file)
    if os.path.exists(health_file):
        os.remove(health_file)

    subprocess.run([script_path], check=False)
    assert os.path.isfile(health_file), f"{health_file} was not created by the script."
    with open(health_file, "r") as f:
        assert f.read().strip() == "STATUS: UNHEALTHY", "Script did not output STATUS: UNHEALTHY when log file is missing."

    # Test 2: Log file exists but has CRITICAL_ERROR
    with open(log_file, "w") as f:
        f.write("Some info\nCRITICAL_ERROR encountered\n")

    subprocess.run([script_path], check=False)
    with open(health_file, "r") as f:
        assert f.read().strip() == "STATUS: UNHEALTHY", "Script did not output STATUS: UNHEALTHY when log file has CRITICAL_ERROR."

    # Test 3: Log file exists and is healthy
    with open(log_file, "w") as f:
        f.write("Normal startup\nINFO: Running\n")

    subprocess.run([script_path], check=False)
    with open(health_file, "r") as f:
        assert f.read().strip() == "STATUS: HEALTHY", "Script did not output STATUS: HEALTHY when log file is healthy."

    # Exercise additional unpredictable contents so the monitor must implement
    # the general exact-substring check rather than recognize fixed fixtures.
    nonce = secrets.token_hex(32)
    cases = [
        (f"INFO {nonce}\nall systems operational\n", "STATUS: HEALTHY"),
        (f"{nonce}\ncritical_error\n", "STATUS: HEALTHY"),
        (f"{nonce}\nCRITICAL-ERROR\n", "STATUS: HEALTHY"),
        (f"prefix-{nonce}-CRITICAL_ERROR-suffix\n", "STATUS: UNHEALTHY"),
        (f"CRITICAL_ERROR\n{nonce}\n", "STATUS: UNHEALTHY"),
        (f"{nonce}\nCRI\nTICAL_ERROR\n", "STATUS: HEALTHY"),
    ]
    for body, expected in cases:
        with open(log_file, "w") as f:
            f.write(body)
        if os.path.exists(health_file):
            os.remove(health_file)
        actual = _run_monitor(script_path, health_file)
        assert actual == expected, \
            f"Monitor returned {actual!r}, expected {expected!r} for generated log content."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
