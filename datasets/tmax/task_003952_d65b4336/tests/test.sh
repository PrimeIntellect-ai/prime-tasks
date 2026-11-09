#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import shutil
import subprocess
import tempfile
import time

import requests

SERVICE_DIR = "/app/legacy-svc"
SERVER = os.path.join(SERVICE_DIR, "server")
EXPECTED_ROUTE = "/api/v1/system/health"


def test_route_h_content():
    path = "/app/legacy-svc/route.h"
    assert os.path.isfile(path), f"File {path} is missing."
    with open(path, "r") as f:
        content = f.read().strip()
    expected = '#define ROUTE_PATH "/api/v1/system/health"'
    assert content == expected, f"Expected {path} to contain exactly '{expected}', but got '{content}'"

    with open("/app/routes.txt", "r") as f:
        active = [line[len("ACTIVE: "):].strip() for line in f if line.startswith("ACTIVE: ")]
    assert len(active) == 1, "Expected exactly one ACTIVE route in /app/routes.txt"
    assert content == f'#define ROUTE_PATH "{active[0]}"', "route.h was not derived from the ACTIVE route"


def test_server_binary_compiled():
    path = SERVER
    assert os.path.isfile(path), f"Compiled binary {path} is missing."
    assert os.access(path, os.X_OK), f"File {path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not a compiled ELF executable"


def test_makefile_rebuilds_exact_server_with_threading_flag():
    makefile = os.path.join(SERVICE_DIR, "Makefile")
    assert os.path.isfile(makefile), f"File {makefile} is missing."

    with tempfile.TemporaryDirectory(prefix="legacy-build-") as tmp:
        build_dir = os.path.join(tmp, "legacy-svc")
        shutil.copytree(SERVICE_DIR, build_dir, ignore=shutil.ignore_patterns("server"))
        result = subprocess.run(
            ["make", "-B", "server"], cwd=build_dir,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, timeout=120
        )
        assert result.returncode == 0, f"The repaired Makefile cannot build server:\n{result.stdout}"
        assert re.search(r"(?<!\S)-pthread(?!\S)", result.stdout), \
            f"The active server build command does not contain -pthread:\n{result.stdout}"
        assert re.search(r"main\.cpp", result.stdout), "The server build command did not compile main.cpp"

        rebuilt = os.path.join(build_dir, "server")
        assert os.path.isfile(rebuilt) and os.access(rebuilt, os.X_OK), "make did not produce an executable server"
        with open(rebuilt, "rb") as f:
            rebuilt_bytes = f.read()
        assert rebuilt_bytes.startswith(b"\x7fELF"), "make produced a non-ELF server artifact"

        with open(SERVER, "rb") as f:
            deployed_bytes = f.read()
        assert hashlib.sha256(deployed_bytes).digest() == hashlib.sha256(rebuilt_bytes).digest(), \
            "The deployed server is not the binary produced by the current source and Makefile"


def test_logrotate_conf():
    path = "/home/user/logrotate.conf"
    assert os.path.isfile(path), f"File {path} is missing."
    with open(path, "r") as f:
        content = f.read()

    assert "/home/user/app.log" in content, f"Expected '/home/user/app.log' in {path}"
    directives = ["daily", "rotate 3", "compress", "missingok", "size 10M"]
    normalized_content = re.sub(r'\s+', ' ', content)

    for directive in directives:
        if directive == "size 10M":
            assert re.search(r'size\s*=?\s*10M', content, re.IGNORECASE), f"Expected 'size 10M' directive in {path}"
        elif directive == "rotate 3":
            assert re.search(r'rotate\s+3', content), f"Expected 'rotate 3' directive in {path}"
        else:
            assert re.search(r'\b' + directive + r'\b', content), f"Expected '{directive}' directive in {path}"


def test_logrotate_configuration_is_active_and_valid():
    path = "/home/user/logrotate.conf"
    with open(path, "r") as f:
        raw = f.read()

    uncommented = "\n".join(line.split("#", 1)[0] for line in raw.splitlines())
    blocks = re.findall(r"([^{}]+)\{([^{}]*)\}", uncommented, flags=re.S)
    target_bodies = []
    for header, body in blocks:
        paths = re.findall(r'"([^"]+)"|(\S+)', header)
        paths = [quoted or bare for quoted, bare in paths]
        if "/home/user/app.log" in paths:
            target_bodies.append(body)

    assert len(target_bodies) == 1, "Expected exactly one active logrotate block for /home/user/app.log"
    body = target_bodies[0]
    lines = [line.strip() for line in body.splitlines() if line.strip()]

    assert any(re.fullmatch(r"daily", line) for line in lines), "daily is not active in the app.log block"
    rotate_values = [int(m.group(1)) for line in lines if (m := re.fullmatch(r"rotate\s+(\d+)", line))]
    assert rotate_values and all(value == 3 for value in rotate_values), "app.log must keep exactly 3 backups"
    assert any(re.fullmatch(r"compress", line) for line in lines), "compress is not active in the app.log block"
    assert not any(re.fullmatch(r"nocompress", line) for line in lines), "nocompress conflicts with compress"
    assert any(re.fullmatch(r"missingok", line) for line in lines), "missingok is not active in the app.log block"
    assert any(re.fullmatch(r"size\s*(?:=\s*)?10M", line, re.I) for line in lines), \
        "size 10M is not active in the app.log block"
    assert not any(re.fullmatch(r"(?:hourly|weekly|monthly|yearly)", line) for line in lines), \
        "A conflicting rotation interval overrides daily"

    with tempfile.TemporaryDirectory(prefix="logrotate-check-") as tmp:
        test_log = os.path.join(tmp, "app.log")
        open(test_log, "a").close()
        rewritten = raw.replace("/home/user/app.log", test_log)
        test_conf = os.path.join(tmp, "logrotate.conf")
        with open(test_conf, "w") as f:
            f.write(rewritten)
        result = subprocess.run(
            ["logrotate", "-d", "-s", os.path.join(tmp, "state"), test_conf],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=20
        )
        assert result.returncode == 0, f"logrotate rejected the configuration:\n{result.stdout}"


def test_service_and_port_forwarding():
    url = "http://127.0.0.1:9090/api/v1/system/health"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        assert False, f"Failed to connect to the service at {url}. Is the server and socat port forwarding running? Error: {e}"

    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}. Response body: {response.text}"
    try:
        data = response.json()
    except ValueError:
        assert False, f"Expected JSON response, got: {response.text}"
    assert data == {"status": "ok"}, f"Expected response body {{'status': 'ok'}}, got {data}"


def test_compiled_service_behavior_and_logging():
    with open("/app/routes.txt", "r") as f:
        route = next(line[len("ACTIVE: "):].strip() for line in f if line.startswith("ACTIVE: "))

    for port in (8080, 9090):
        response = requests.get(f"http://127.0.0.1:{port}{route}", timeout=5)
        assert response.status_code == 200
        assert response.json() == {"status": "ok"}

    wrong = requests.get(f"http://127.0.0.1:9090{route}/verifier-not-a-route", timeout=5)
    assert wrong.status_code == 404, "The service incorrectly returns the fixed success response for an unknown route"

    log_path = "/home/user/app.log"
    before = os.path.getsize(log_path) if os.path.exists(log_path) else 0
    response = requests.get(f"http://127.0.0.1:9090{route}", timeout=5)
    assert response.status_code == 200
    time.sleep(0.2)
    assert os.path.isfile(log_path), "The service did not create /home/user/app.log"
    with open(log_path, "rb") as f:
        f.seek(before)
        appended = f.read().decode("utf-8", errors="replace")
    assert "Request received" in appended, "A request did not append the expected service log entry"


def test_processes_running():
    try:
        ps_output = subprocess.check_output(["ps", "aux"]).decode("utf-8")
    except subprocess.CalledProcessError:
        assert False, "Failed to execute 'ps aux'"

    assert "server" in ps_output or "./server" in ps_output, "The 'server' process does not appear to be running."
    assert "socat" in ps_output, "The 'socat' process does not appear to be running."


def test_running_processes_are_the_required_programs():
    server_pids = []
    socat_pids = []
    expected_socat = os.path.realpath(shutil.which("socat"))

    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        proc = os.path.join("/proc", name)
        try:
            exe = os.path.realpath(os.readlink(os.path.join(proc, "exe")))
            with open(os.path.join(proc, "cmdline"), "rb") as f:
                args = [part.decode(errors="replace") for part in f.read().split(b"\0") if part]
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue

        try:
            if os.path.samefile(os.path.join(proc, "exe"), SERVER):
                server_pids.append(int(name))
        except (FileNotFoundError, OSError):
            pass

        if exe == expected_socat:
            command = " ".join(args)
            has_listener = re.search(r"TCP(?:4)?-LISTEN:9090(?:,|\s|$)", command, re.I)
            has_target = re.search(r"TCP(?:4)?:127\.0\.0\.1:8080(?:,|\s|$)", command, re.I)
            if has_listener and has_target:
                socat_pids.append(int(name))

    assert server_pids, "No running process is executing /app/legacy-svc/server"
    assert socat_pids, "No real socat process forwards 0.0.0.0:9090 to 127.0.0.1:8080"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
