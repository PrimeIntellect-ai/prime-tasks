#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import concurrent.futures
import json
import os
import re
import subprocess
import urllib.request

import pytest


def _listener_owners(port):
    """Return PIDs owning TCP listen sockets on the requested port."""
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10:
                        local_port = int(fields[1].split(":")[1], 16)
                        state = fields[3]
                        if local_port == port and state == "0A":
                            inodes.add(fields[9])
        except FileNotFoundError:
            pass

    owners = set()
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    owners.add(int(pid))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return owners


def _proc_info(pid):
    try:
        exe = os.path.realpath(f"/proc/{pid}/exe")
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            args = [x.decode(errors="replace") for x in f.read().split(b"\0") if x]
        return exe, args
    except (FileNotFoundError, PermissionError, ProcessLookupError):
        return "", []


def _flag_values(args, flag):
    values = []
    for i, arg in enumerate(args):
        if arg == flag and i + 1 < len(args):
            values.append(args[i + 1])
        elif arg.startswith(flag) and arg != flag:
            values.append(arg[len(flag):])
    return values


def _http_ok():
    try:
        with urllib.request.urlopen("http://127.0.0.1:8080/", timeout=3) as response:
            if response.status != 200:
                return False
            payload = json.loads(response.read().decode())
            return payload.get("status") == "ok"
    except Exception:
        return False


def test_logrotate_config_valid():
    """Verify that the logrotate config exists and has valid syntax."""
    conf_path = "/app/logrotate.conf"
    assert os.path.exists(conf_path), f"Logrotate config not found at {conf_path}"

    # Preserve the original syntax validation.
    cmd = ["logrotate", "-d", "-s", "/app/logs/logrotate.status", conf_path]
    result = subprocess.run(cmd, capture_output=True, text=True)
    assert result.returncode == 0, (
        f"logrotate syntax check failed for {conf_path}.\n"
        f"Return code: {result.returncode}\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )

    assert os.path.isfile("/app/logs/logrotate.status"), (
        "The required logrotate status file was not created"
    )

    with open(conf_path) as f:
        raw = f.read()
    text = re.sub(r"(?m)#.*$", "", raw)
    assert not re.search(r"(?mi)^\s*su(?:\s|$)", text), "logrotate config must not contain su directives"

    blocks = re.findall(r"([^{}]*)\{([^{}]*)\}", text, flags=re.S)
    backend_blocks = [body for header, body in blocks if re.search(r"(?:^|\s)[\"']?/app/logs/backend\.log[\"']?(?:\s|$)", header)]
    assert backend_blocks, "No logrotate block for /app/logs/backend.log"
    body = backend_blocks[-1]

    sizes = re.findall(r"(?mi)^\s*size\s+(\S+)\s*$", body)
    rotations = re.findall(r"(?mi)^\s*rotate\s+(\d+)\s*$", body)
    assert sizes and sizes[-1].lower() == "100k", "backend.log must rotate at size 100k"
    assert rotations and rotations[-1] == "3", "backend.log must keep exactly 3 backups"
    assert re.search(r"(?mi)^\s*compress\s*$", body), "backend.log backups must be compressed"
    assert not re.search(r"(?mi)^\s*nocompress\s*$", body), "nocompress contradicts the compression requirement"
    custom_compressors = re.findall(r"(?mi)^\s*compresscmd\s+(\S+)\s*$", body)
    assert all(os.path.basename(x) == "gzip" for x in custom_compressors), "Compression must use gzip"


def test_ssh_authentication_and_tunnel():
    auth = subprocess.run(
        [
            "/usr/bin/ssh", "-i", "/app/ssh/deploy_key", "-p", "2222",
            "-o", "BatchMode=yes", "-o", "IdentitiesOnly=yes",
            "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null",
            "-o", "ConnectTimeout=5", "user@127.0.0.1", "true",
        ],
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert auth.returncode == 0, f"Deployment-key SSH authentication failed: {auth.stderr}"

    owners = _listener_owners(8081)
    assert owners, "Nothing is listening on the required tunnel port 8081"

    valid_tunnel = False
    for pid in owners:
        exe, args = _proc_info(pid)
        if exe != os.path.realpath("/usr/bin/ssh"):
            continue
        forwards = _flag_values(args, "-L")
        ports = _flag_values(args, "-p")
        identities = _flag_values(args, "-i")
        has_forward = any(re.fullmatch(r"(?:(?:127\.0\.0\.1|localhost):)?8081:127\.0\.0\.1:9090", value) for value in forwards)
        has_target = any(value in ("user@127.0.0.1", "user@localhost") for value in args)
        if has_forward and "2222" in ports and "/app/ssh/deploy_key" in identities and "-N" in args and has_target:
            valid_tunnel = True
            break
    assert valid_tunnel, "Port 8081 is not owned by the required background OpenSSH tunnel"


def test_nginx_configuration_and_live_requests():
    result = subprocess.run(
        ["/usr/sbin/nginx", "-T", "-c", "/app/nginx/nginx.conf"],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"Nginx configuration is invalid: {result.stderr}"
    effective = re.sub(r"(?m)#.*$", "", result.stdout)
    assert re.search(r"proxy_pass\s+http://127\.0\.0\.1:8081/?\s*;", effective), (
        "Nginx must proxy requests to http://127.0.0.1:8081"
    )

    owners = _listener_owners(8080)
    assert owners, "Nothing is listening on Nginx port 8080"
    assert any(_proc_info(pid)[0] == os.path.realpath("/usr/sbin/nginx") for pid in owners), (
        "Port 8080 is not owned by Nginx"
    )

    with concurrent.futures.ThreadPoolExecutor(max_workers=25) as pool:
        outcomes = list(pool.map(lambda _: _http_ok(), range(500)))
    rate = sum(outcomes) / 500.0
    assert rate >= 0.95, f"Independent 500-request success rate {rate:.3f} is below 0.95"


def test_benchmark_success_rate():
    """Preserve validation of the agent-created results and independently execute the benchmark."""
    results_path = "/app/benchmark_results.json"
    assert os.path.exists(results_path), f"Benchmark results file not found at {results_path}"

    with open(results_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Failed to parse {results_path} as JSON: {e}")

    assert "success_rate" in data, f"'success_rate' key missing in {results_path}"
    try:
        success_rate = float(data["success_rate"])
    except (ValueError, TypeError):
        pytest.fail(f"'success_rate' is not a valid float: {data['success_rate']}")

    threshold = 0.95
    assert success_rate >= threshold, (
        f"Benchmark success_rate {success_rate} is below the required threshold of {threshold}. "
        "This indicates Nginx, the SSH tunnel, or the backend are not functioning correctly."
    )

    run = subprocess.run(
        ["/bin/bash", "/app/scripts/benchmark.sh"],
        capture_output=True,
        text=True,
        timeout=180,
    )
    assert run.returncode == 0, f"benchmark.sh failed: {run.stderr}"
    try:
        fresh = json.loads(run.stdout)
        fresh_rate = float(fresh["success_rate"])
    except (json.JSONDecodeError, KeyError, ValueError, TypeError) as exc:
        pytest.fail(f"benchmark.sh did not produce valid success-rate JSON: {exc}; output={run.stdout!r}")
    assert fresh_rate >= threshold, f"Fresh benchmark success_rate {fresh_rate} is below {threshold}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
