#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import filecmp
import json
import os
import re
import shutil
import subprocess
import urllib.error
import urllib.request

import pytest

V2 = "/home/user/deploy/releases/v2"
CURRENT = "/home/user/deploy/current"
SOURCE = "/app/upstream-service-1.2.0"
BINARY = os.path.join(V2, "upstream-service")
NGINX_CONFIG = "/home/user/nginx/nginx.conf"
METRICS = "/home/user/metrics.txt"


def configured_upstream_port():
    with open(NGINX_CONFIG, "r") as f:
        config = f.read()
    matches = re.findall(r"proxy_pass\s+http://127\.0\.0\.1:(\d+)\s*;", config)
    assert matches, "Could not find the local proxy_pass port in nginx.conf"
    assert len(set(matches)) == 1, "nginx.conf has ambiguous upstream ports"
    port = int(matches[0])
    assert port == 8081, "The staging NGINX upstream must remain 127.0.0.1:8081"
    return port


def listener_inodes(port):
    result = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                lines = f.readlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) < 10:
                continue
            local_port = int(fields[1].rsplit(":", 1)[1], 16)
            state = fields[3]
            if local_port == port and state == "0A":
                result.add(fields[9])
    return result


def pids_owning_sockets(inodes):
    owners = set()
    wanted = {f"socket:[{inode}]" for inode in inodes}
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    if os.readlink(os.path.join(fd_dir, fd)) in wanted:
                        owners.add(int(entry))
                        break
                except OSError:
                    pass
        except OSError:
            pass
    return owners


def test_v2_directory_exists():
    assert os.path.isdir(V2), f"Release directory not found at {V2}"

    executables = [
        f for f in os.listdir(V2)
        if os.path.isfile(os.path.join(V2, f))
        and os.access(os.path.join(V2, f), os.X_OK)
    ]
    assert len(executables) > 0, f"No executable binary found in {V2}"
    assert os.path.isfile(BINARY), f"Compiled upstream-service binary not found at {BINARY}"
    assert os.access(BINARY, os.X_OK), f"{BINARY} is not executable"
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY} is not a native compiled binary"


def test_symlink_updated():
    assert os.path.islink(CURRENT), f"{CURRENT} must be a symlink"
    resolved_target = os.path.realpath(CURRENT)
    expected_path = os.path.realpath(V2)
    assert resolved_target == expected_path, (
        f"Symlink {CURRENT} should resolve to {expected_path}, "
        f"but resolves to {resolved_target}"
    )


def test_nginx_port_and_release_were_built_from_source():
    configured_upstream_port()
    assert os.path.isfile(os.path.join(SOURCE, "Cargo.toml")), "Cargo.toml is missing"
    assert os.path.isfile(os.path.join(SOURCE, "src/main.rs")), "Rust main source is missing"

    target_dir = os.path.join(SOURCE, "target")
    clean = subprocess.run(
        ["cargo", "clean"], cwd=SOURCE, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, text=True, timeout=60
    )
    assert clean.returncode == 0, f"cargo clean failed:\n{clean.stdout}"

    build = subprocess.run(
        ["cargo", "build", "--release"], cwd=SOURCE, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, text=True, timeout=300
    )
    assert build.returncode == 0, f"Fresh release build failed:\n{build.stdout}"

    rebuilt = os.path.join(target_dir, "release", "upstream-service")
    assert os.path.isfile(rebuilt), "Fresh build did not produce upstream-service"
    assert filecmp.cmp(rebuilt, BINARY, shallow=False), (
        "The deployed v2 binary is not the release binary produced from the current Rust source"
    )


def test_service_process_is_deployed_binary_started_from_current():
    port = configured_upstream_port()
    inodes = listener_inodes(port)
    assert inodes, f"No process is listening on the configured upstream port {port}"

    matching = []
    for pid in pids_owning_sockets(inodes):
        try:
            exe_matches = os.path.samefile(f"/proc/{pid}/exe", BINARY)
            cwd_matches = os.path.samefile(f"/proc/{pid}/cwd", CURRENT)
            if exe_matches and cwd_matches:
                matching.append(pid)
        except OSError:
            pass

    assert matching, (
        f"The listener on port {port} is not the deployed {BINARY} process "
        f"started from {CURRENT}"
    )


def test_metrics_success_rate():
    assert os.path.isfile(METRICS), (
        f"Metrics file not found at {METRICS}. Did you run the load test script?"
    )
    with open(METRICS, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Metrics file {METRICS} does not contain valid JSON.")

    assert "success_rate" in data, f"'success_rate' key not found in {METRICS}"
    success_rate = data.get("success_rate", 0.0)
    assert isinstance(success_rate, (int, float)), "success_rate must be a number"
    assert success_rate >= 1.0, f"Expected success_rate >= 1.0, but got {success_rate}"

    successes = 0
    for _ in range(10):
        try:
            with urllib.request.urlopen("http://127.0.0.1:8080", timeout=2) as response:
                if response.getcode() == 200:
                    successes += 1
        except Exception:
            pass
    assert successes == 10, f"Independent load check succeeded only {successes}/10 times"

    load = subprocess.run(
        ["python3", "/home/user/test_load.py"], stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, text=True, timeout=30
    )
    assert load.returncode == 0, f"Load test script failed:\n{load.stdout}"
    with open(METRICS, "r") as f:
        rerun_data = json.load(f)
    assert rerun_data.get("success_rate") == 1.0, (
        f"The actual load test reported {rerun_data.get('success_rate')}"
    )


def test_service_running_and_proxying():
    try:
        response = urllib.request.urlopen("http://127.0.0.1:8080", timeout=2)
        status_code = response.getcode()
        assert status_code == 200, f"Expected HTTP 200 from NGINX proxy, got {status_code}"
    except urllib.error.HTTPError as e:
        pytest.fail(
            f"NGINX returned an HTTP error: {e.code} {e.reason}. "
            "The upstream service might still be broken or misconfigured."
        )
    except Exception as e:
        pytest.fail(f"Failed to connect to NGINX on port 8080: {e}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
