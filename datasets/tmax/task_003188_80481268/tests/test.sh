#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import secrets
import socket
import stat
import subprocess
import time


def run_systemctl(*args):
    return subprocess.run(
        ["systemctl", "--user", *args], capture_output=True, text=True
    )


def main_pid():
    result = run_systemctl("show", "exporter.service", "--property=MainPID", "--value")
    assert result.returncode == 0, result.stderr
    value = result.stdout.strip()
    assert value.isdigit() and int(value) > 0, f"Invalid MainPID: {value!r}"
    return int(value)


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def test_source_was_repaired_and_installed_binary_was_built_from_it():
    source_path = "/app/metrics-exporter/server.cpp"
    makefile_path = "/app/metrics-exporter/Makefile"
    built_path = "/app/metrics-exporter/exporter"
    installed_path = "/home/user/bin/exporter"

    assert os.path.isfile(source_path), "server.cpp is missing"
    assert os.path.isfile(makefile_path), "Provided Makefile is missing"
    assert os.path.isfile(installed_path), "Installed exporter is missing"
    assert os.access(installed_path, os.X_OK), "Installed exporter is not executable"

    with open(source_path, "r") as f:
        source = f.read()
    assert "127.0.0.2" not in source, "server.cpp still contains the incorrect bind address"
    assert re.search(r'BIND_IP\s*=\s*"127\.0\.0\.1"', source), \
        "server.cpp does not set BIND_IP to 127.0.0.1"
    assert "sleep_for" not in source, "The artificial request-loop delay remains in server.cpp"

    with open(makefile_path, "r") as f:
        makefile = f.read().strip()
    expected_makefile = "exporter: server.cpp\n\tg++ -O2 -pthread server.cpp -o exporter"
    assert makefile == expected_makefile, "The provided Makefile was modified"

    result = subprocess.run(
        ["make", "-B", "exporter"], cwd="/app/metrics-exporter",
        capture_output=True, text=True
    )
    assert result.returncode == 0, f"The repaired source does not build with the provided Makefile: {result.stderr}"
    assert os.path.isfile(built_path)

    with open(built_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Makefile output is not an ELF binary"
    with open(installed_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Installed exporter is not an ELF binary"
    assert sha256(built_path) == sha256(installed_path), \
        "/home/user/bin/exporter was not built from the repaired source using the provided Makefile"


def test_systemd_service_configured_enabled_and_running():
    service_file = "/home/user/.config/systemd/user/exporter.service"
    assert os.path.isfile(service_file), f"Service file {service_file} does not exist."

    with open(service_file, "r") as f:
        content = f.read()

    # Preserve the original checks.
    assert "Restart=always" in content, "Service file missing Restart=always"
    assert "RestartSec=2" in content, "Service file missing RestartSec=2"
    assert "/home/user/bin/exporter" in content, "Service file does not execute the correct binary path"

    directives = []
    for line in content.splitlines():
        line = line.strip()
        if line and not line.startswith(("#", ";")) and "=" in line:
            directives.append(line)
    assert "ExecStart=/home/user/bin/exporter" in directives, "ExecStart is not configured correctly"
    assert "Restart=always" in directives, "Restart=always is not an active directive"
    assert "RestartSec=2" in directives, "RestartSec=2 is not an active directive"

    result = run_systemctl("is-enabled", "exporter.service")
    assert result.returncode == 0 and result.stdout.strip() == "enabled", \
        f"Service is not enabled: {result.stdout.strip()} {result.stderr.strip()}"

    result = run_systemctl("is-active", "exporter.service")
    assert result.stdout.strip() == "active", f"Service is not active. Status: {result.stdout.strip()}"

    pid = main_pid()
    proc_exe = f"/proc/{pid}/exe"
    assert os.path.exists(proc_exe), "The service MainPID is not running"
    assert sha256(proc_exe) == sha256("/home/user/bin/exporter"), \
        "The active service is not running the installed exporter binary"


def assert_invalid_deploy(args):
    deploy_script = "/home/user/deploy.sh"
    sentinel = f"sentinel-{secrets.token_hex(8)}"
    with open("/home/user/version.txt", "w") as f:
        f.write(sentinel + "\n")
    before_pid = main_pid()

    result = subprocess.run([deploy_script, *args], capture_output=True, text=True)
    assert result.returncode != 0, f"deploy.sh accepted invalid argument list: {args!r}"
    time.sleep(0.2)
    with open("/home/user/version.txt", "r") as f:
        assert f.read().strip() == sentinel, "Invalid invocation modified version.txt"
    assert main_pid() == before_pid, "Invalid invocation restarted the service"


def run_valid_deploy(version):
    deploy_script = "/home/user/deploy.sh"
    before_pid = main_pid()
    result = subprocess.run([deploy_script, version], capture_output=True, text=True)
    assert result.returncode == 0, f"deploy.sh failed to execute. Error: {result.stderr}"

    version_file = "/home/user/version.txt"
    assert os.path.isfile(version_file), f"Version file {version_file} was not created."
    with open(version_file, "r") as f:
        written_version = f.read().strip()
    assert written_version == version, f"Expected version {version!r}, got {written_version!r}"

    time.sleep(0.4)
    result = run_systemctl("is-active", "exporter.service")
    assert result.stdout.strip() == "active", "Service is not active after running deploy.sh."
    assert main_pid() != before_pid, "deploy.sh did not restart exporter.service"


def test_deploy_script_behavior():
    deploy_script = "/home/user/deploy.sh"
    assert os.path.isfile(deploy_script), f"Deploy script {deploy_script} does not exist."
    assert os.stat(deploy_script).st_mode & stat.S_IXUSR, f"Deploy script {deploy_script} is not executable."

    assert_invalid_deploy([])
    assert_invalid_deploy(["one", "two"])

    # Preserve the original fixed-value assertion, then exercise an unpredictable value.
    run_valid_deploy("v1.5-test")
    run_valid_deploy(f"audit-{secrets.token_hex(12)}")


def fetch_metrics():
    request = b"GET /metrics HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n"
    with socket.create_connection(("127.0.0.1", 8080), timeout=0.2) as s:
        s.settimeout(0.2)
        s.sendall(request)
        chunks = []
        while True:
            chunk = s.recv(4096)
            if not chunk:
                break
            chunks.append(chunk)
            if sum(map(len, chunks)) > 16384:
                raise AssertionError("Metrics response is unexpectedly large")
    data = b"".join(chunks)
    head, separator, body = data.partition(b"\r\n\r\n")
    assert separator, "Malformed HTTP response"
    lines = head.split(b"\r\n")
    assert lines[0] == b"HTTP/1.1 200 OK", f"Unexpected HTTP status: {lines[0]!r}"
    assert any(line.lower() == b"content-type: text/plain" for line in lines[1:]), \
        "Metrics response has the wrong Content-Type"
    assert body.strip() == b"metrics_value 42", f"Unexpected metrics body: {body!r}"


def test_throughput_metric():
    start_time = time.monotonic()
    deadline = start_time + 2.0
    count = 0
    while time.monotonic() < deadline:
        try:
            fetch_metrics()
            count += 1
        except (OSError, socket.timeout):
            pass

    elapsed = time.monotonic() - start_time
    throughput = count / elapsed
    assert throughput >= 1000, \
        f"Throughput metric failed: achieved {throughput:.2f} rps, expected >= 1000 rps."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
