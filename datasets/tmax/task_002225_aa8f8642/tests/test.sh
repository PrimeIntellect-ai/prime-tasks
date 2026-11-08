#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import glob
import http.client
import json
import os
import re
import signal
import socket
import subprocess
import time

EXPECTED = "database connection timeout in eu west one"
HOME = "/home/user"
SOURCE = f"{HOME}/dashboard_backend.c"
CONFIG = f"{HOME}/backend.conf"
INCIDENT = f"{HOME}/incident_text.txt"
DEPLOY = f"{HOME}/deploy.sh"
BINARY = f"{HOME}/backend.bin"
LOG = f"{HOME}/backend.log"
BACKUPS = f"{HOME}/backups"


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def http_incident(port, timeout=2):
    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=timeout)
    try:
        conn.request("GET", "/")
        response = conn.getresponse()
        body = response.read()
        assert response.status == 200, f"Expected HTTP 200 OK, got {response.status}"
        try:
            data = json.loads(body.decode("utf-8"))
        except Exception as exc:
            raise AssertionError(f"Response body is not valid JSON: {body!r}: {exc}")
        assert data.keys() == {"incident"}, f"Unexpected JSON object: {data!r}"
        assert isinstance(data["incident"], str), "incident value is not a string"
        return data["incident"]
    finally:
        conn.close()


def tcp_incident(port, timeout=2):
    with socket.create_connection(("127.0.0.1", port), timeout=timeout) as sock:
        sock.settimeout(timeout)
        chunks = []
        while True:
            chunk = sock.recv(4096)
            if not chunk:
                break
            chunks.append(chunk)
    data = b"".join(chunks)
    assert data, "Received empty response from TCP server"
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise AssertionError(f"TCP response is not UTF-8: {exc}")


def wait_for_service(http_port, tcp_port, expected, timeout=8):
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        try:
            assert http_incident(http_port, 0.5) == expected
            assert tcp_incident(tcp_port, 0.5) == expected + "\n"
            return
        except Exception as exc:
            last = exc
            time.sleep(0.1)
    raise AssertionError(f"Service did not become ready with exact responses: {last}")


def backend_pids():
    result = []
    me = os.getpid()
    for entry in glob.glob("/proc/[0-9]*"):
        pid = int(entry.rsplit("/", 1)[1])
        if pid == me:
            continue
        try:
            exe = os.readlink(f"{entry}/exe")
            argv = open(f"{entry}/cmdline", "rb").read().split(b"\0")
        except (OSError, PermissionError):
            continue
        if exe.removesuffix(" (deleted)") == BINARY or BINARY.encode() in argv:
            result.append(pid)
    return result


def stop_backend_processes():
    pids = backend_pids()
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and any(os.path.exists(f"/proc/{p}") for p in pids):
        time.sleep(0.05)
    for pid in pids:
        if os.path.exists(f"/proc/{pid}"):
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass


def run_deploy(timeout=20):
    try:
        return subprocess.run(
            [DEPLOY], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, timeout=timeout
        )
    except subprocess.TimeoutExpired as exc:
        raise AssertionError(
            "deploy.sh did not return promptly; the new service must be backgrounded "
            "with output redirected"
        ) from exc


def matching_backup(content, since_ns):
    matches = []
    for path in glob.glob(os.path.join(BACKUPS, "backend_*.bin")):
        try:
            if os.stat(path).st_mtime_ns >= since_ns and open(path, "rb").read() == content:
                matches.append(path)
        except OSError:
            pass
    return matches


def main():
    # Preserve the original existence and configuration assertions, but require exact values.
    assert os.path.exists(DEPLOY), f"Deployment script {DEPLOY} does not exist"
    assert os.path.isfile(DEPLOY), f"{DEPLOY} is not a file"
    assert os.access(DEPLOY, os.X_OK), f"Deployment script {DEPLOY} is not executable"
    assert os.path.isdir(BACKUPS), f"Backup directory {BACKUPS} does not exist"
    assert os.path.isfile(CONFIG), f"Config file {CONFIG} does not exist"
    assert os.path.isfile(SOURCE), f"C source {SOURCE} does not exist"
    assert os.path.isfile(INCIDENT), f"Incident transcription {INCIDENT} does not exist"

    config_text = open(CONFIG, encoding="utf-8").read()
    assert "HTTP_PORT=8080" in config_text
    assert "TCP_PORT=8081" in config_text
    assert "INCIDENT_FILE=/home/user/incident_text.txt" in config_text
    config_lines = config_text.splitlines()
    assert config_lines == [
        "HTTP_PORT=8080",
        "TCP_PORT=8081",
        "INCIDENT_FILE=/home/user/incident_text.txt",
    ], f"backend.conf must contain exactly the requested key-value lines: {config_lines!r}"

    incident_raw = open(INCIDENT, encoding="utf-8").read()
    assert incident_raw.rstrip("\r\n") == EXPECTED, "The audio transcription is not exact"
    assert not incident_raw.startswith((" ", "\t", "\r", "\n")), "Transcription has leading whitespace"

    # Preserve the live HTTP/TCP checks, strengthening them to exact answers including 'one'.
    assert http_incident(8080) == EXPECTED
    assert tcp_incident(8081) == EXPECTED + "\n"

    # Compile and execute the submitted C source against changed ports and incident contents.
    test_binary = "/tmp/dashboard_backend_verifier.bin"
    compile_result = subprocess.run(
        ["gcc", SOURCE, "-o", test_binary, "-pthread"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    assert compile_result.returncode == 0, f"C source did not compile: {compile_result.stderr}"
    assert open(test_binary, "rb").read(4) == b"\x7fELF", "Compiled backend is not an ELF executable"

    original_config = open(CONFIG, "rb").read()
    original_incident = open(INCIDENT, "rb").read()
    port1 = free_port()
    port2 = free_port()
    while port2 == port1:
        port2 = free_port()
    dynamic_text = f"verifier dynamic incident {os.getpid()}"
    child = None
    try:
        with open(INCIDENT, "w", encoding="utf-8") as f:
            f.write(dynamic_text)
        with open(CONFIG, "w", encoding="utf-8") as f:
            f.write(f"HTTP_PORT={port1}\nTCP_PORT={port2}\nINCIDENT_FILE={INCIDENT}\n")
        child = subprocess.Popen([test_binary], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        wait_for_service(port1, port2, dynamic_text)
        assert child.poll() is None, "Compiled C backend exited unexpectedly"
    finally:
        if child is not None and child.poll() is None:
            child.terminate()
            try:
                child.wait(timeout=2)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()
        with open(CONFIG, "wb") as f:
            f.write(original_config)
        with open(INCIDENT, "wb") as f:
            f.write(original_incident)

    # Exercise deploy.sh with a distinguishable running backend. It must back it up,
    # leave it running on compile failure, then terminate it via SIGTERM on success.
    stop_backend_processes()
    marker = "/tmp/verifier_graceful_term"
    try:
        os.unlink(marker)
    except FileNotFoundError:
        pass
    helper_source = "/tmp/verifier_old_backend.c"
    with open(helper_source, "w") as f:
        f.write(r'''#include <signal.h>
#include <fcntl.h>
#include <unistd.h>
static void done(int sig) {
    int fd = open("/tmp/verifier_graceful_term", O_WRONLY|O_CREAT|O_TRUNC, 0666);
    if (fd >= 0) { write(fd, "TERM\n", 5); close(fd); }
    _exit(0);
}
int main(void) {
    struct sigaction sa = {0}; sa.sa_handler = done;
    sigaction(SIGTERM, &sa, 0);
    for (;;) pause();
}
''')
    helper_compile = subprocess.run(
        ["gcc", helper_source, "-o", BINARY],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    assert helper_compile.returncode == 0, helper_compile.stderr
    helper_bytes = open(BINARY, "rb").read()
    helper = subprocess.Popen([BINARY], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.2)
    assert helper.poll() is None

    source_bytes = open(SOURCE, "rb").read()
    try:
        failed_backup_time = time.time_ns()
        with open(SOURCE, "ab") as f:
            f.write(b"\n#error verifier_induced_compile_failure\n")
        failed = run_deploy()
        assert failed.returncode != 0, "deploy.sh reported success despite a compilation error"
        assert helper.poll() is None, "deploy.sh stopped the running backend before compilation succeeded"
        assert not os.path.exists(marker), "Running backend received SIGTERM after failed compilation"
        assert matching_backup(helper_bytes, failed_backup_time), "Running backend was not backed up before deployment"
        assert os.path.isfile(BINARY) and open(BINARY, "rb").read() == helper_bytes, \
            "Failed compilation destroyed or replaced the current backend.bin"
    finally:
        with open(SOURCE, "wb") as f:
            f.write(source_bytes)

    time.sleep(1.1)  # Avoid collisions in scripts using one-second timestamps.
    successful_backup_time = time.time_ns()
    successful = run_deploy()
    assert successful.returncode == 0, f"Valid deployment failed: {successful.stderr}"
    try:
        helper.wait(timeout=5)
    except subprocess.TimeoutExpired:
        raise AssertionError("Old backend was not terminated after successful compilation")
    assert os.path.exists(marker), "Old backend was not gracefully terminated with SIGTERM"
    assert matching_backup(helper_bytes, successful_backup_time), "Successful deployment did not back up the old binary"
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK), "New backend.bin is missing or not executable"
    assert open(BINARY, "rb").read(4) == b"\x7fELF", "Deployed backend.bin is not a compiled executable"
    assert os.path.isfile(LOG), "deploy.sh did not redirect service output to backend.log"
    wait_for_service(8080, 8081, EXPECTED)
    assert backend_pids(), "The deployed /home/user/backend.bin process is not running"


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
