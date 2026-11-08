#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import shlex
import subprocess
from pathlib import Path


def test_monitor_go_exists():
    """Test that the Go monitoring agent source file exists."""
    path = "/home/user/monitor.go"
    assert os.path.exists(path), "/home/user/monitor.go does not exist."
    assert os.path.isfile(path) and not os.path.islink(path), f"{path} must be a regular file."


def test_storage_metric_json():
    """Test that storage_metric.json is generated correctly based on device_storage.txt."""
    txt_path = "/home/user/device_storage.txt"
    json_path = "/home/user/storage_metric.json"

    assert os.path.exists(txt_path), f"{txt_path} is missing, cannot verify."
    assert os.path.exists(json_path), f"{json_path} was not generated."

    with open(txt_path, "r") as f:
        content = f.read().strip()

    match = re.search(r"storage_available_kb=(\d+)", content)
    assert match is not None, f"Could not parse storage_available_kb from {txt_path}"

    kb_val = int(match.group(1))
    expected_mb = kb_val // 1024

    with open(json_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{json_path} does not contain valid JSON."

    assert "storage_mb" in data, f"'storage_mb' key missing in {json_path}"
    assert data["storage_mb"] == expected_mb, f"Expected storage_mb to be {expected_mb}, got {data['storage_mb']}"


def test_monitor_go_executes_and_processes_fresh_inputs():
    """Execute the submitted Go source on unpredictable inputs and verify its output."""
    source = Path("/home/user/monitor.go")
    txt_path = Path("/home/user/device_storage.txt")
    json_path = Path("/home/user/storage_metric.json")

    assert source.is_file() and not source.is_symlink(), f"{source} must be a regular file."

    original_txt = txt_path.read_bytes() if txt_path.exists() else None
    original_json = json_path.read_bytes() if json_path.exists() else None

    base = secrets.randbelow(5_000_000) + 10_000
    values = [base * 1024 + 17, (base + 137) * 1024 + 1023, 511]

    try:
        for kb_val in values:
            txt_path.write_text(f"storage_available_kb={kb_val}\n", encoding="utf-8")
            if json_path.exists() or json_path.is_symlink():
                json_path.unlink()

            result = subprocess.run(
                ["go", "run", str(source)],
                cwd="/home/user",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=45,
            )
            assert result.returncode == 0, (
                f"go run failed for storage_available_kb={kb_val}:\n{result.stderr}"
            )
            assert json_path.is_file() and not json_path.is_symlink(), (
                f"The program did not create a regular {json_path} file."
            )

            try:
                data = json.loads(json_path.read_text(encoding="utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError) as exc:
                assert False, f"The program produced invalid JSON: {exc}"

            assert isinstance(data, dict), "The generated JSON must be an object."
            assert set(data.keys()) == {"storage_mb"}, (
                "The generated JSON must contain exactly the storage_mb key."
            )
            assert type(data["storage_mb"]) is int, "storage_mb must be a JSON integer."
            assert data["storage_mb"] == kb_val // 1024, (
                f"For {kb_val} KB, expected {kb_val // 1024} MB, got {data['storage_mb']}."
            )
    finally:
        if original_txt is None:
            if txt_path.exists() or txt_path.is_symlink():
                txt_path.unlink()
        else:
            txt_path.write_bytes(original_txt)

        if original_json is None:
            if json_path.exists() or json_path.is_symlink():
                json_path.unlink()
        else:
            if json_path.is_symlink():
                json_path.unlink()
            json_path.write_bytes(original_json)


def test_setup_iot_script():
    """Test that setup_iot.sh exists and contains the required commands."""
    script_path = "/home/user/setup_iot.sh"
    assert os.path.exists(script_path), f"{script_path} does not exist."

    with open(script_path, "r") as f:
        script_content = f.read()

    # Preserve the original content assertions.
    assert re.search(r"(groupadd|addgroup)\s+sensor-net", script_content), \
        "setup_iot.sh is missing the command to create the sensor-net group."

    assert re.search(r"(useradd|adduser).*sensor-net.*metrics-agent", script_content), \
        "setup_iot.sh is missing the command to create the metrics-agent user in the sensor-net group."

    assert re.search(r"ip\s+route\s+add\s+172\.16\.0\.0/12\s+via\s+10\.0\.0\.1\s+dev\s+eth0", script_content), \
        "setup_iot.sh is missing the correct 'ip route add' command."

    has_ssh = "ssh " in script_content
    has_f = re.search(r"\B-f\b", script_content)
    has_N = re.search(r"\B-N\b", script_content)
    has_L = re.search(r"\B-L\s+8080:172\.16\.5\.5:80\b", script_content)
    has_target = "tunnel@10.0.0.254" in script_content

    assert has_ssh and has_f and has_N and has_L and has_target, \
        "setup_iot.sh is missing the correct SSH tunnel command with -f, -N, -L 8080:172.16.5.5:80, and tunnel@10.0.0.254."

    # Validate four real, one-per-line shell commands in the required order.
    assert os.path.isfile(script_path) and not os.path.islink(script_path), \
        f"{script_path} must be a regular file."

    commands = []
    for line_number, raw_line in enumerate(script_content.splitlines(), 1):
        stripped = raw_line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        try:
            tokens = shlex.split(raw_line, comments=True, posix=True)
        except ValueError as exc:
            assert False, f"Invalid shell syntax on line {line_number}: {exc}"
        if tokens:
            commands.append((line_number, tokens))

    assert len(commands) == 4, \
        f"Expected exactly four command lines, found {len(commands)}."

    group = commands[0][1]
    assert group in (["groupadd", "sensor-net"], ["addgroup", "sensor-net"]), \
        "The first command must create only the sensor-net system group."

    user = commands[1][1]
    valid_user_commands = [
        ["useradd", "-g", "sensor-net", "metrics-agent"],
        ["useradd", "--gid", "sensor-net", "metrics-agent"],
        ["useradd", "--gid=sensor-net", "metrics-agent"],
        ["adduser", "--ingroup", "sensor-net", "metrics-agent"],
    ]
    assert user in valid_user_commands, \
        "The second command must create metrics-agent with sensor-net as its primary group."

    route = commands[2][1]
    assert route == ["ip", "route", "add", "172.16.0.0/12", "via", "10.0.0.1", "dev", "eth0"], \
        "The third command must be the specified ip route command."

    ssh = commands[3][1]
    assert ssh and ssh[0] == "ssh", "The fourth command must invoke ssh."
    assert ssh[-1] == "tunnel@10.0.0.254", \
        "The SSH destination must be tunnel@10.0.0.254 and must follow the options."

    options = ssh[1:-1]
    assert len(options) == 4, "The SSH command must contain only -f, -N, and the required -L forwarding option."
    assert options.count("-f") == 1 and options.count("-N") == 1, \
        "The SSH command must contain -f and -N exactly once."
    assert options.count("-L") == 1, "The SSH command must contain a separate -L option exactly once."
    l_index = options.index("-L")
    assert l_index + 1 < len(options) and options[l_index + 1] == "8080:172.16.5.5:80", \
        "The -L option must forward 8080 to 172.16.5.5:80."
    consumed = {l_index, l_index + 1}
    remaining = [token for i, token in enumerate(options) if i not in consumed]
    assert sorted(remaining) == ["-N", "-f"], \
        "The SSH command contains unsupported or misplaced arguments."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
