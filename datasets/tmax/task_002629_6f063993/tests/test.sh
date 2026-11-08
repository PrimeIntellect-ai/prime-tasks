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
import os
import re
import shutil
import signal
import subprocess
import time

import pytest
import requests

SOURCE_DIR = "/app/iot-gateway-2.1.0"
SOURCE_GATEWAY = SOURCE_DIR + "/gatewayd"
INSTALLED_GATEWAY = "/home/user/local/bin/gatewayd"
SUPERVISOR = "/home/user/supervisor.sh"
DEPLOY = "/home/user/deploy.sh"


def _proc_cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return f.read().replace(b"\0", b" ").decode(errors="replace")
    except OSError:
        return ""


def _proc_uid(pid):
    try:
        with open(f"/proc/{pid}/status") as f:
            for line in f:
                if line.startswith("Uid:"):
                    return int(line.split()[1])
    except OSError:
        pass
    return None


def _listener_entries(port):
    wanted = f"{port:04X}"
    sockets = []
    for table, family in (("/proc/net/tcp", "tcp4"), ("/proc/net/tcp6", "tcp6")):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    address, found_port = fields[1].split(":")
                    if found_port.upper() == wanted and fields[3] == "0A":
                        sockets.append((fields[9], family, address.upper()))
        except OSError:
            pass

    results = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            links = {os.readlink(os.path.join(fd_dir, fd)) for fd in os.listdir(fd_dir)}
        except OSError:
            continue
        for inode, family, address in sockets:
            if f"socket:[{inode}]" in links:
                results.append((int(name), family, address))
    return results


def _kill_pid(pid):
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass


def _clean_processes():
    # Remove anything the agent left on the required ports, then remove all
    # processes owned by the unprivileged deployment user.
    for port in (8080, 9090):
        for pid, _, _ in _listener_entries(port):
            _kill_pid(pid)
    for name in os.listdir("/proc"):
        if name.isdigit() and _proc_uid(int(name)) == 1000:
            _kill_pid(int(name))
    deadline = time.time() + 3
    while time.time() < deadline:
        if not _listener_entries(8080) and not _listener_entries(9090):
            return
        time.sleep(0.05)
    assert not _listener_entries(8080), "Could not clear the existing listener on port 8080"
    assert not _listener_entries(9090), "Could not clear the existing listener on port 9090"


def _run_as_user(argv, **kwargs):
    command = [
        "/usr/sbin/runuser", "-u", "user", "--", "/usr/bin/env",
        "HOME=/home/user", "PATH=/usr/local/bin:/usr/bin:/bin",
        "GATEWAY_AUTH_TOKEN=", *argv,
    ]
    return subprocess.run(command, **kwargs)


def _wait_for_listener(port, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        entries = _listener_entries(port)
        if entries:
            return entries
        time.sleep(0.05)
    return []


def _ancestors(pid):
    seen = set()
    while pid > 1 and pid not in seen:
        seen.add(pid)
        yield pid, _proc_cmdline(pid)
        try:
            with open(f"/proc/{pid}/stat") as f:
                pid = int(f.read().split()[3])
        except (OSError, ValueError, IndexError):
            return


def _assert_gateway_process(pid):
    cmdline = _proc_cmdline(pid)
    assert INSTALLED_GATEWAY in cmdline, (
        f"Port 8080 is not being served by the installed gatewayd: {cmdline!r}"
    )
    try:
        with open(f"/proc/{pid}/environ", "rb") as f:
            environment = f.read().split(b"\0")
    except OSError as exc:
        pytest.fail(f"Could not inspect gatewayd environment: {exc}")
    assert b"GATEWAY_AUTH_TOKEN=edge2024" in environment, (
        "gatewayd was not started with GATEWAY_AUTH_TOKEN=edge2024"
    )
    assert any(SUPERVISOR in cmd for _, cmd in _ancestors(pid)), (
        "gatewayd is not a child of /home/user/supervisor.sh"
    )


def test_gatewayd_installed():
    """Preserve the original installed-binary assertions."""
    assert os.path.isfile(INSTALLED_GATEWAY), f"Expected installed binary at {INSTALLED_GATEWAY} is missing."
    assert os.access(INSTALLED_GATEWAY, os.X_OK), f"The binary at {INSTALLED_GATEWAY} is not executable."


def test_scripts_exist_and_executable():
    """Preserve the original script assertions and require Bash scripts."""
    for path, label in ((SUPERVISOR, "Supervisor"), (DEPLOY, "Deploy")):
        assert os.path.isfile(path), f"{label} script {path} is missing."
        assert os.access(path, os.X_OK), f"{label} script {path} is not executable."
        with open(path, "rb") as f:
            first_line = f.readline().decode(errors="replace")
        assert first_line.startswith("#!") and "bash" in first_line, f"{path} is not a Bash script"


def test_makefile_and_fresh_deployment():
    """Exercise the patched Makefile and execute deploy.sh from a clean state."""
    _clean_processes()
    shutil.rmtree("/home/user/local", ignore_errors=True)

    result = _run_as_user(
        ["/usr/bin/make", "-C", SOURCE_DIR, "install"],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=15,
    )
    assert result.returncode == 0, f"Patched make install failed as user:\n{result.stdout}"
    assert os.path.isfile(INSTALLED_GATEWAY), "The Makefile's default install target did not install under /home/user/local"
    assert os.access(INSTALLED_GATEWAY, os.X_OK), "make install did not produce an executable gatewayd"
    assert open(INSTALLED_GATEWAY, "rb").read() == open(SOURCE_GATEWAY, "rb").read(), (
        "make install did not install the supplied gatewayd"
    )

    # Remove the installed binary again so deploy.sh must perform installation.
    os.unlink(INSTALLED_GATEWAY)
    trace_path = "/tmp/deploy-xtrace.log"
    with open(trace_path, "wb") as trace:
        result = _run_as_user(
            ["/bin/bash", "-x", DEPLOY],
            stdout=subprocess.DEVNULL, stderr=trace, timeout=10,
        )
    assert result.returncode == 0, f"{DEPLOY} exited with status {result.returncode}"

    with open(trace_path, errors="replace") as f:
        trace = f.read()
    assert re.search(r"(?m)^\+.*(?:^|[ /])make(?:\s+[^\n]*)?\s+install(?:\s|$)", trace), (
        "deploy.sh did not execute make install"
    )
    assert SUPERVISOR in trace, "deploy.sh did not start /home/user/supervisor.sh"
    assert re.search(r"(?m)^\+.*(?:^|[ /])socat(?:\s|$)", trace), "deploy.sh did not start socat"

    assert os.path.isfile(INSTALLED_GATEWAY), "deploy.sh did not reinstall gatewayd"
    assert os.access(INSTALLED_GATEWAY, os.X_OK), "The gatewayd installed by deploy.sh is not executable"
    assert open(INSTALLED_GATEWAY, "rb").read() == open(SOURCE_GATEWAY, "rb").read(), (
        "deploy.sh did not install the supplied gatewayd"
    )

    gateway_entries = _wait_for_listener(8080)
    forward_entries = _wait_for_listener(9090)
    assert gateway_entries, "deploy.sh did not start a listener on 127.0.0.1:8080"
    assert forward_entries, "deploy.sh did not start a listener on 0.0.0.0:9090"

    gateway_pid, gateway_family, gateway_address = gateway_entries[0]
    assert gateway_family == "tcp4" and gateway_address == "0100007F", (
        "gatewayd is not bound to 127.0.0.1:8080"
    )
    _assert_gateway_process(gateway_pid)

    socat_candidates = [entry for entry in forward_entries if entry[1] == "tcp4" and entry[2] == "00000000"]
    assert socat_candidates, "Port 9090 is not listening on all IPv4 interfaces (0.0.0.0)"
    socat_pid = socat_candidates[0][0]
    try:
        socat_exe = os.path.basename(os.readlink(f"/proc/{socat_pid}/exe"))
    except OSError:
        socat_exe = ""
    socat_cmd = _proc_cmdline(socat_pid).upper()
    assert socat_exe == "socat", f"Port 9090 is not owned by socat (owner command: {_proc_cmdline(socat_pid)!r})"
    assert "9090" in socat_cmd and "127.0.0.1:8080" in socat_cmd, (
        f"socat is not configured to forward 9090 to 127.0.0.1:8080: {_proc_cmdline(socat_pid)!r}"
    )

    # Crash gatewayd and verify that the supervisor restarts it after the
    # required delay rather than merely leaving a one-shot server running.
    started = time.monotonic()
    _kill_pid(gateway_pid)
    replacement = None
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        entries = _listener_entries(8080)
        new_entries = [entry for entry in entries if entry[0] != gateway_pid]
        if new_entries:
            replacement = new_entries[0]
            break
        time.sleep(0.05)
    assert replacement is not None, "supervisor.sh did not restart gatewayd after it crashed"
    elapsed = time.monotonic() - started
    assert elapsed >= 0.65, f"gatewayd restarted after only {elapsed:.2f}s; supervisor must sleep for 1 second"
    _assert_gateway_process(replacement[0])


def test_gateway_health_endpoint():
    """Preserve the original health check after the clean deployment."""
    url = "http://127.0.0.1:9090/health"
    try:
        response = requests.get(url, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the gateway via socat at {url}. Error: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}. Response: {response.text}"
    assert "OK - Authorized" in response.text, f"Expected 'OK - Authorized' in response body, got: {response.text}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
