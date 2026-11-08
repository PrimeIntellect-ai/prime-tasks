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
import signal
import socket
import subprocess
import tempfile
import time

import pytest
import requests

BINARY = "/home/user/microserver_bin"
PROJECT = "/app/vendored/microserver"

EXPECTED_SERVER_CPP = '''#include "httplib.h"
#include <iostream>

int main(int argc, char** argv) {
    if (argc != 3) {
        std::cerr << "Usage: " << argv[0] << " <port> <base_dir>\\n";
        return 1;
    }
    int port = std::stoi(argv[1]);
    std::string base_dir = argv[2];

    httplib::Server svr;
    if (!svr.set_mount_point("/", base_dir)) {
        std::cerr << "Failed to mount base directory\\n";
        return 1;
    }
    svr.Get("/health", [](const httplib::Request &, httplib::Response &res) {
        res.set_content("OK", "text/plain");
    });

    std::cout << "Starting server on port " << port << "...\\n";
    svr.listen("127.0.0.1", port);
    return 0;
}
'''


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def matching_pids(fragment):
    found = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            with open(f"/proc/{name}/cmdline", "rb") as f:
                cmdline = f.read().replace(b"\0", b" ").decode(errors="replace")
            if fragment in cmdline:
                found.append(int(name))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return found


def test_binary_is_rebuilt_vendored_cpp_artifact():
    assert os.path.isfile(BINARY), f"Binary {BINARY} does not exist. Did you compile and move it?"
    assert os.access(BINARY, os.X_OK), f"Binary {BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "microserver_bin must be a compiled ELF binary, not a script."

    source = os.path.join(PROJECT, "server.cpp")
    makefile = os.path.join(PROJECT, "Makefile")
    assert os.path.isfile(source)
    assert os.path.isfile(makefile)
    with open(source, encoding="utf-8") as f:
        assert f.read() == EXPECTED_SERVER_CPP, "The vendored server.cpp must not be replaced."
    with open(makefile, encoding="utf-8") as f:
        make_text = f.read()
    assert re.search(r"(?:-pthread|-lpthread)(?:\s|$)", make_text), "Makefile is missing pthread linkage."
    assert "server.cpp" in make_text and "$(CXX)" in make_text, "Makefile must compile the vendored C++ source."

    result = subprocess.run(
        ["make", "-B", "microserver"], cwd=PROJECT,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=60
    )
    assert result.returncode == 0, f"The repaired Makefile does not build successfully:\n{result.stdout}"
    rebuilt = os.path.join(PROJECT, "microserver")
    assert os.path.isfile(rebuilt) and os.access(rebuilt, os.X_OK)
    assert sha256(BINARY) == sha256(rebuilt), \
        "microserver_bin is not the binary produced by the repaired vendored project."


def test_binary_serves_arbitrary_files_when_executed_directly():
    token = os.urandom(18).hex()
    filename = f"probe-{os.urandom(8).hex()}.txt"
    with tempfile.TemporaryDirectory() as base:
        with open(os.path.join(base, filename), "w", encoding="utf-8") as f:
            f.write(token)
        with socket.socket() as s:
            s.bind(("127.0.0.1", 0))
            port = s.getsockname()[1]
        proc = subprocess.Popen(
            [BINARY, str(port), base], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        try:
            deadline = time.time() + 5
            last_error = None
            while time.time() < deadline:
                if proc.poll() is not None:
                    pytest.fail(f"microserver_bin exited early with status {proc.returncode}")
                try:
                    r = requests.get(f"http://127.0.0.1:{port}/{filename}", timeout=0.5)
                    if r.status_code == 200:
                        assert r.text == token
                        health = requests.get(f"http://127.0.0.1:{port}/health", timeout=1)
                        assert health.status_code == 200
                        assert health.text == "OK"
                        return
                except requests.RequestException as e:
                    last_error = e
                time.sleep(0.1)
            pytest.fail(f"Compiled binary did not serve the randomized test directory: {last_error}")
        finally:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()


def test_filesystem_setup():
    assert os.path.isdir("/home/user/public_html")
    with open("/home/user/public_html/index.html", "rb") as f:
        assert f.read() == b"DEPLOYMENT_SUCCESS"
    with open("/home/user/public_html/data.txt", "rb") as f:
        assert f.read() == b"SENSITIVE_DATA"


def test_start_server_script_and_running_environment():
    path = "/home/user/start_server.sh"
    assert os.path.isfile(path), f"Script {path} does not exist."
    assert os.access(path, os.X_OK), f"Script {path} is not executable."
    subprocess.run(["bash", "-n", path], check=True)
    with open(path, "r") as f:
        content = f.read()
    assert "TZ=Pacific/Auckland" in content or "TZ='Pacific/Auckland'" in content or 'TZ="Pacific/Auckland"' in content
    assert "LC_ALL=en_NZ.UTF-8" in content or "LC_ALL='en_NZ.UTF-8'" in content or 'LC_ALL="en_NZ.UTF-8"' in content

    output = subprocess.check_output(["pgrep", "-f", "microserver_bin.*9090"], text=True)
    assert output.strip(), "microserver_bin process is not running on port 9090."

    valid = []
    for pid in matching_pids("microserver_bin"):
        try:
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                args = [x.decode(errors="replace") for x in f.read().split(b"\0") if x]
            with open(f"/proc/{pid}/environ", "rb") as f:
                env = dict(x.split(b"=", 1) for x in f.read().split(b"\0") if b"=" in x)
            exe = os.path.realpath(f"/proc/{pid}/exe")
            if (exe == BINARY and len(args) >= 3 and args[1:] == ["9090", "/home/user/public_html"]
                    and env.get(b"TZ") == b"Pacific/Auckland"
                    and env.get(b"LC_ALL") == b"en_NZ.UTF-8"):
                valid.append(pid)
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    assert valid, "The running compiled server lacks the required arguments or applied TZ/LC_ALL environment."


def test_socat_process_running():
    try:
        output = subprocess.check_output(["pgrep", "-f", "socat.*8080.*9090"], text=True)
        assert output.strip(), "socat process forwarding 8080 to 9090 is not running."
    except subprocess.CalledProcessError:
        pytest.fail("socat process forwarding 8080 to 9090 is not running.")


def test_http_endpoints_via_socat_and_dynamic_file():
    time.sleep(1)
    expected = {
        "index.html": "DEPLOYMENT_SUCCESS",
        "data.txt": "SENSITIVE_DATA",
    }
    for name, body in expected.items():
        try:
            r = requests.get(f"http://127.0.0.1:8080/{name}", timeout=2)
        except requests.RequestException as e:
            pytest.fail(f"Failed to fetch {name} through socat: {e}")
        assert r.status_code == 200
        assert r.text.strip() == body

    r = requests.get("http://127.0.0.1:8080/health", timeout=2)
    assert r.status_code == 200

    name = f"live-{os.urandom(8).hex()}.txt"
    value = os.urandom(20).hex()
    path = os.path.join("/home/user/public_html", name)
    try:
        with open(path, "w", encoding="utf-8") as f:
            f.write(value)
        r = requests.get(f"http://127.0.0.1:8080/{name}", timeout=2)
        assert r.status_code == 200 and r.text == value, "Server does not serve newly created files."
    finally:
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass


def test_monitor_exists_runs_continuously_and_updates_status():
    script = "/home/user/monitor.sh"
    status = "/home/user/status.log"
    assert os.path.isfile(script), "monitor.sh does not exist."
    assert os.access(script, os.X_OK), "monitor.sh is not executable."
    subprocess.run(["bash", "-n", script], check=True)
    with open(script, encoding="utf-8") as f:
        text = f.read()
    assert "curl" in text and "http://127.0.0.1:8080/health" in text, \
        "monitor.sh must check the required health URL with curl."
    assert matching_pids("/home/user/monitor.sh"), "monitor.sh is not continuously running in the background."

    with open(status, "w", encoding="utf-8") as f:
        f.write("DOWN")
    deadline = time.time() + 5
    while time.time() < deadline:
        try:
            with open(status, encoding="utf-8") as f:
                if f.read().strip() == "UP":
                    break
        except FileNotFoundError:
            pass
        time.sleep(0.2)
    else:
        pytest.fail("The running monitor did not replace status.log with UP after a healthy response.")

    assert matching_pids("/home/user/monitor.sh"), "monitor.sh stopped instead of continuing to run."
    assert os.path.isfile(status)
    with open(status, encoding="utf-8") as f:
        assert f.read().strip() == "UP"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
