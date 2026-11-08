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
import secrets
import socket
import subprocess
import time

import pytest
import requests

PROJECT = "/home/user/project"
LIBCORE = PROJECT + "/clib/libcore.a"
SERVER = PROJECT + "/bin/server"


def test_libcore_a_exists():
    assert os.path.isfile(LIBCORE), "The static library libcore.a was not successfully built at /home/user/project/clib/libcore.a"


def test_libcore_is_a_real_make_built_archive(tmp_path):
    subprocess.run(["make", "clean", "all"], cwd=PROJECT + "/clib", check=True,
                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)

    listing = subprocess.run(["ar", "t", LIBCORE], check=True, capture_output=True, text=True).stdout.splitlines()
    assert "core.o" in listing, f"libcore.a does not contain core.o: {listing}"

    probe = tmp_path / "probe.c"
    probe.write_text('#include "core.h"\nint main(void) { return process_data(21) == 42 ? 0 : 1; }\n')
    executable = tmp_path / "probe"
    subprocess.run([
        "gcc", "-I" + PROJECT + "/clib", str(probe), LIBCORE, "-o", str(executable)
    ], check=True, capture_output=True, text=True)
    subprocess.run([str(executable)], check=True)


def test_server_binary_exists():
    assert os.path.isfile(SERVER), "The Go binary was not successfully built at /home/user/project/bin/server"


def test_server_binary_is_minimal_go_executable():
    assert os.access(SERVER, os.X_OK), "bin/server is not executable"
    with open(SERVER, "rb") as f:
        assert f.read(4) == b"\x7fELF", "bin/server is not an ELF executable"

    result = subprocess.run(["go", "version", "-m", SERVER], check=True, capture_output=True, text=True)
    assert "path\tproject" in result.stdout, f"bin/server is not the project Go executable:\n{result.stdout}"
    assert "-tags=minimal" in result.stdout, f"bin/server was not built with the minimal build tag:\n{result.stdout}"


def test_sources_build_with_required_command_and_preserve_server_api(tmp_path):
    api_test = PROJECT + "/server/verifier_api_test.go"
    try:
        with open(api_test, "w") as f:
            f.write('''package server_test

import (
    "testing"
    "project/config"
    "project/server"
)

func TestExportedServerAPIAndDefaults(t *testing.T) {
    s := server.NewServer(config.AppConfig{})
    if s == nil || s.Config.MaxConns != 100 {
        t.Fatalf("NewServer/defaults API is broken: %#v", s)
    }
}
''')
        subprocess.run(["go", "test", "-tags", "minimal", "./server"], cwd=PROJECT,
                       check=True, capture_output=True, text=True)
        rebuilt = str(tmp_path / "server")
        subprocess.run(["go", "build", "-tags", "minimal", "-o", rebuilt], cwd=PROJECT,
                       check=True, capture_output=True, text=True)
        exercise_server(rebuilt)
    finally:
        try:
            os.remove(api_test)
        except FileNotFoundError:
            pass


def listening_socket_inodes(port):
    found = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    inode = fields[9]
                    if state == "0A" and int(local.rsplit(":", 1)[1], 16) == port:
                        found.add(inode)
        except FileNotFoundError:
            pass
    return found


def test_port_8443_is_owned_by_compiled_server():
    inodes = listening_socket_inodes(8443)
    assert inodes, "No process is listening on port 8443"

    matching_pids = []
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            owns_socket = any(
                os.readlink(os.path.join(fd_dir, fd)) in {f"socket:[{inode}]" for inode in inodes}
                for fd in os.listdir(fd_dir)
            )
            if owns_socket and os.path.samefile(f"/proc/{pid}/exe", SERVER):
                matching_pids.append(pid)
        except (FileNotFoundError, PermissionError, ProcessLookupError, OSError):
            continue

    assert matching_pids, "Port 8443 is not being served by /home/user/project/bin/server"


def test_server_running_and_unauthorized():
    url = "http://127.0.0.1:8443/ping"
    try:
        response = requests.get(url, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {url}. Is it running on the correct port? Error: {e}")

    assert response.status_code == 401, f"Expected 401 Unauthorized when missing token, but got {response.status_code}"


def test_server_running_and_authorized():
    url = "http://127.0.0.1:8443/ping"
    headers = {"Authorization": "Bearer AlphaBravo99"}
    try:
        response = requests.get(url, headers=headers, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {url}. Is it running on the correct port? Error: {e}")

    assert response.status_code == 200, f"Expected 200 OK with correct token, but got {response.status_code}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Expected JSON response, but got: {response.text}")

    assert data.get("status") == "ok", f"Expected response JSON {{'status': 'ok'}}, but got {data}"


def unused_local_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def exercise_server(executable):
    port = unused_local_port()
    token = "Verifier-" + secrets.token_hex(18)
    env = os.environ.copy()
    env["SERVER_PORT"] = str(port)
    env["API_TOKEN"] = token
    proc = subprocess.Popen([executable], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    url = f"http://127.0.0.1:{port}/ping"
    session = requests.Session()
    session.trust_env = False
    try:
        deadline = time.time() + 8
        while time.time() < deadline:
            assert proc.poll() is None, f"{executable} exited before serving requests"
            try:
                response = session.get(url, timeout=0.3)
                break
            except requests.exceptions.RequestException:
                time.sleep(0.1)
        else:
            pytest.fail(f"{executable} did not start listening on its configured port")

        assert response.status_code == 401
        wrong = session.get(url, headers={"Authorization": "Bearer " + secrets.token_hex(18)}, timeout=2)
        assert wrong.status_code == 401
        correct = session.get(url, headers={"Authorization": "Bearer " + token}, timeout=2)
        assert correct.status_code == 200
        assert correct.json().get("status") == "ok"
        assert proc.poll() is None
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=3)


def test_submitted_binary_uses_runtime_environment():
    exercise_server(SERVER)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
