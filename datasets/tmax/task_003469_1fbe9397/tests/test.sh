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
import json
import os
import re
import secrets
import signal
import socket
import subprocess
import time
from pathlib import Path

import pytest
import requests

HOME = Path("/home/user")
ROUTES_JSON = Path("/app/routes.json")
VIDEO = "/app/signal.mp4"


def decode_program():
    colors = {
        "INC": (255, 0, 0),
        "DEC": (0, 255, 0),
        "MUL": (0, 0, 255),
        "RET": (255, 255, 255),
    }
    program = []
    for second in range(120):
        raw = subprocess.check_output(
            [
                "ffmpeg", "-v", "error", "-ss", str(second), "-i", VIDEO,
                "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1",
            ],
            timeout=10,
        )
        assert raw, f"Could not decode frame at timestamp {second}.0"
        pixels = len(raw) // 3
        rgb = tuple(sum(raw[channel::3]) / pixels for channel in range(3))
        instruction, distance = min(
            ((name, sum((rgb[i] - target[i]) ** 2 for i in range(3)))
             for name, target in colors.items()),
            key=lambda item: item[1],
        )
        assert distance < 2500, f"Unrecognized frame color at {second}.0: {rgb}"
        program.append(instruction)
        if instruction == "RET":
            return program
    pytest.fail("No RET instruction found in the video")


PROGRAM = decode_program()
ROUTE = json.loads(ROUTES_JSON.read_text())["exec_route"]


def execute_vm(initial):
    accumulator = initial
    for instruction in PROGRAM:
        if instruction == "INC":
            accumulator += 1
        elif instruction == "DEC":
            accumulator -= 1
        elif instruction == "MUL":
            accumulator *= 2
        elif instruction == "RET":
            return accumulator
    raise AssertionError("Decoded program did not return")


def listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) >= 10 and fields[3] == "0A":
                if int(fields[1].rsplit(":", 1)[1], 16) == port:
                    inodes.add(fields[9])

    result = set()
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / "fd").iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    result.add(int(proc.name))
                    break
        except OSError:
            continue
    return result


def wait_for_server(port, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            response = requests.get(f"http://127.0.0.1:{port}/invalid", timeout=0.25)
            if response.status_code:
                return
        except requests.RequestException:
            time.sleep(0.05)
    pytest.fail(f"Server did not begin listening on port {port}")


def test_router_h_exists():
    """Verify that the router header file was generated."""
    assert os.path.exists("/home/user/router.h"), "Missing /home/user/router.h"


def test_router_h_contents_and_source_include():
    header = (HOME / "router.h").read_text()
    match = re.search(r'^\s*#\s*define\s+EXEC_ROUTE\s+"([^"\n]+)"\s*$', header, re.MULTILINE)
    assert match, "router.h does not define EXEC_ROUTE as a C string"
    assert match.group(1) == ROUTE, "EXEC_ROUTE does not match /app/routes.json"

    source = (HOME / "server.c").read_text()
    assert re.search(r'^\s*#\s*include\s*["<]router\.h[">]', source, re.MULTILINE), \
        "server.c does not include router.h"


def test_server_binary_exists():
    """Verify that the C server was compiled and is executable."""
    assert os.path.exists("/home/user/server.c"), "Missing /home/user/server.c"
    assert os.path.exists("/home/user/server"), "Missing /home/user/server binary"
    assert os.access("/home/user/server", os.X_OK), "/home/user/server is not executable"
    assert (HOME / "server").is_file(), "/home/user/server is not a regular file"
    assert (HOME / "server").read_bytes()[:4] == b"\x7fELF", "/home/user/server is not a compiled ELF binary"
    assert (HOME / "server").stat().st_mtime >= (HOME / "server.c").stat().st_mtime, \
        "/home/user/server is older than server.c"
    assert (HOME / "server").stat().st_mtime >= (HOME / "router.h").stat().st_mtime, \
        "/home/user/server is older than router.h"


def test_server_exec_route_10():
    """Verify the execution route with init=10 returns the correct VM output."""
    try:
        response = requests.get("http://127.0.0.1:8080/api/exec?init=10", timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to server at 127.0.0.1:8080: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    assert response.text.strip() == "23", f"Expected response body '23', got '{response.text}'"


def test_server_exec_route_5():
    """Verify the execution route with init=5 returns the correct VM output."""
    try:
        response = requests.get("http://127.0.0.1:8080/api/exec?init=5", timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to server at 127.0.0.1:8080: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    # init=5 -> INC(6) -> INC(7) -> MUL(14) -> DEC(13) -> RET(13)
    assert response.text.strip() == "13", f"Expected response body '13', got '{response.text}'"


def test_server_404_route():
    """Verify that an invalid route returns a 404 Not Found."""
    try:
        response = requests.get("http://127.0.0.1:8080/invalid", timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to server at 127.0.0.1:8080: {e}")

    assert response.status_code == 404, f"Expected status code 404 for invalid route, got {response.status_code}"


def test_submitted_binary_is_the_listener_and_handles_derived_inputs():
    pids = listener_pids(8080)
    assert pids, "No process is listening on port 8080"
    assert any(
        os.path.exists(f"/proc/{pid}/exe") and os.path.samefile(f"/proc/{pid}/exe", HOME / "server")
        for pid in pids
    ), "/home/user/server is not the process listening on port 8080"

    rng = secrets.SystemRandom()
    values = set()
    while len(values) < 10:
        value = rng.randint(-100000, 100000)
        if value not in (5, 10):
            values.add(value)

    for initial in values:
        response = requests.get(
            f"http://127.0.0.1:8080{ROUTE}", params={"init": initial}, timeout=2
        )
        assert response.status_code == 200
        assert response.text.strip() == str(execute_vm(initial))

    invalid = f"/invalid-{secrets.token_hex(10)}"
    assert requests.get(f"http://127.0.0.1:8080{invalid}", timeout=2).status_code == 404


def test_server_source_compiles_and_runs_same_service(tmp_path):
    # Redirect only bind(2) calls for port 8080, allowing the rebuilt source to be
    # exercised without disturbing the required submitted server on port 8080.
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        test_port = probe.getsockname()[1]

    wrapper = tmp_path / "bind_wrapper.c"
    wrapper.write_text(r'''
#include <arpa/inet.h>
#include <netinet/in.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>

int __real_bind(int, const struct sockaddr *, socklen_t);
int __wrap_bind(int fd, const struct sockaddr *address, socklen_t length) {
    if (address && address->sa_family == AF_INET && length >= sizeof(struct sockaddr_in)) {
        struct sockaddr_in changed;
        memcpy(&changed, address, sizeof(changed));
        if (ntohs(changed.sin_port) == 8080) {
            const char *value = getenv("VERIFIER_PORT");
            if (value) changed.sin_port = htons((unsigned short)atoi(value));
            return __real_bind(fd, (const struct sockaddr *)&changed, sizeof(changed));
        }
    }
    return __real_bind(fd, address, length);
}
''')
    rebuilt = tmp_path / "server_from_source"
    subprocess.run(
        [
            "gcc", "-std=c11", "-O2", "-I/home/user", "/home/user/server.c",
            str(wrapper), "-Wl,--wrap=bind", "-o", str(rebuilt),
        ],
        check=True,
        timeout=20,
    )

    env = os.environ.copy()
    env["VERIFIER_PORT"] = str(test_port)
    process = subprocess.Popen(
        [str(rebuilt)], cwd="/home/user", env=env,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    try:
        wait_for_server(test_port)
        rng = secrets.SystemRandom()
        values = set()
        while len(values) < 6:
            value = rng.randint(-200000, 200000)
            if value not in (5, 10):
                values.add(value)
        for initial in values:
            response = requests.get(
                f"http://127.0.0.1:{test_port}{ROUTE}", params={"init": initial}, timeout=2
            )
            assert response.status_code == 200
            assert response.text.strip() == str(execute_vm(initial))
        assert requests.get(
            f"http://127.0.0.1:{test_port}/missing-{secrets.token_hex(8)}", timeout=2
        ).status_code == 404
    finally:
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        for pid in listener_pids(test_port):
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
