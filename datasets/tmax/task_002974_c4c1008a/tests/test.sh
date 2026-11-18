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
import math
import os
import random
import signal
import subprocess
import time
from pathlib import Path

import pytest
import requests

PORT_HEX = format(9090, "04X")
SERVER = Path("/home/user/server")


def stop_port_9090():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) >= 10 and fields[1].upper().endswith(":" + PORT_HEX) and fields[3] == "0A":
                inodes.add(fields[9])

    pids = set()
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit() or int(proc.name) == os.getpid():
            continue
        try:
            for fd in (proc / "fd").iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(proc.name))
        except OSError:
            pass

    for sig in (signal.SIGTERM, signal.SIGKILL):
        for pid in list(pids):
            try:
                os.kill(pid, sig)
            except ProcessLookupError:
                pass
        time.sleep(0.4)


def expected_zeta(iterations, value):
    result = value
    for i in range(iterations):
        result = result * 1.05 + i * 0.1
    return result


def request_with_retries(params, process):
    url = "http://127.0.0.1:9090/zeta"
    last_error = None
    for _ in range(10):
        if process.poll() is not None:
            pytest.fail(f"/home/user/server exited with status {process.returncode}")
        try:
            return requests.get(url, params=params, timeout=2)
        except requests.exceptions.RequestException as exc:
            last_error = exc
            time.sleep(0.25)
    pytest.fail(f"Failed to connect to the server at 127.0.0.1:9090: {last_error}")


def check_response(response, expected):
    assert response.status_code == 200, (
        f"Expected HTTP 200, got {response.status_code}. Response text: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response text: {response.text}")
    assert "result" in data, f"JSON response missing 'result' key. Response data: {data}"
    assert set(data) == {"result"}, f"Response must contain only the result field: {data}"
    actual = data["result"]
    assert isinstance(actual, (int, float)) and not isinstance(actual, bool), (
        f"'result' must be a number, got {type(actual)}"
    )
    assert math.isclose(actual, expected, rel_tol=1e-5, abs_tol=1e-7), (
        f"Expected result ~{expected}, got {actual}"
    )
    return actual


def clean_environment():
    env = os.environ.copy()
    env.pop("LD_LIBRARY_PATH", None)
    env.pop("LD_PRELOAD", None)
    return env


def terminate(process):
    if process is None:
        return
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=2)


def test_final_state():
    stop_port_9090()

    build = subprocess.run(
        ["make", "-B", "-C", "/home/user"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=60,
    )
    assert build.returncode == 0, f"make failed:\n{build.stdout}"
    assert SERVER.is_file(), "/home/user/server was not produced"
    assert os.access(SERVER, os.X_OK), "/home/user/server is not executable"
    assert SERVER.read_bytes()[:4] == b"\x7fELF", "/home/user/server is not an ELF executable"

    symbols = subprocess.run(
        ["readelf", "-Ws", str(SERVER)], text=True, capture_output=True, check=True
    ).stdout
    assert any("UND" in line and "compute_zeta_core" in line for line in symbols.splitlines()), (
        "The executable does not import the discovered compute_zeta_core ABI symbol"
    )

    linked = subprocess.run(
        ["ldd", str(SERVER)], text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, env=clean_environment(), timeout=10
    )
    assert linked.returncode == 0, f"Unable to resolve executable dependencies:\n{linked.stdout}"
    assert "not found" not in linked.stdout, f"Unresolved dependency:\n{linked.stdout}"
    assert "/app/liblegacy_math.so" in linked.stdout, (
        f"The legacy library is not linked/resolved from /app:\n{linked.stdout}"
    )

    process = None
    try:
        process = subprocess.Popen(
            [str(SERVER)], cwd="/home/user", env=clean_environment(),
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )

        # Preserve the original fixed assertion.
        response = request_with_retries({"iter": 5, "val": 2.0}, process)
        actual = check_response(response, 3.603825625)
        assert math.isclose(actual, 3.603825625, rel_tol=1e-5), (
            f"Expected result ~3.603825625, got {actual}"
        )

        # Exercise values selected at verification time and derive every answer.
        rng = random.SystemRandom()
        cases = [(0, -3.25), (1, 8.125), (9, 0.375)]
        cases.extend((rng.randint(2, 14), rng.uniform(-20.0, 20.0)) for _ in range(4))
        for iterations, value in cases:
            response = request_with_retries({"iter": iterations, "val": value}, process)
            check_response(response, expected_zeta(iterations, value))
    finally:
        terminate(process)
        stop_port_9090()

    # Interpose the imported ABI once to prove requests actually invoke it rather
    # than returning a constant or independently hardcoded transformation.
    shim_source = Path("/tmp/zeta_probe.c")
    shim_library = Path("/tmp/zeta_probe.so")
    probe_log = Path("/tmp/zeta_probe.log")
    probe_log.unlink(missing_ok=True)
    shim_source.write_text(r'''
#include <fcntl.h>
#include <stdio.h>
#include <unistd.h>

double compute_zeta_core(int iter, double val) {
  int fd = open("/tmp/zeta_probe.log", O_WRONLY | O_CREAT | O_APPEND, 0600);
  if (fd >= 0) {
    dprintf(fd, "%d %.17g\n", iter, val);
    close(fd);
  }
  return ((double) iter * 13.0) - (val * 7.25) + 0.3141592653589793;
}
''')
    compile_probe = subprocess.run(
        ["gcc", "-shared", "-fPIC", str(shim_source), "-o", str(shim_library)],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT
    )
    assert compile_probe.returncode == 0, compile_probe.stdout

    probe_iter = random.SystemRandom().randint(17, 41)
    probe_val = random.SystemRandom().uniform(-9.0, 9.0)
    probe_expected = probe_iter * 13.0 - probe_val * 7.25 + 0.3141592653589793
    probe_env = clean_environment()
    probe_env["LD_PRELOAD"] = str(shim_library)
    process = None
    try:
        process = subprocess.Popen(
            [str(SERVER)], cwd="/home/user", env=probe_env,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        response = request_with_retries({"iter": probe_iter, "val": probe_val}, process)
        check_response(response, probe_expected)
        assert probe_log.exists(), "The legacy ABI function was not invoked"
        calls = probe_log.read_text().splitlines()
        assert calls, "The legacy ABI function was not invoked"
        logged_iter, logged_val = calls[-1].split()
        assert int(logged_iter) == probe_iter
        assert math.isclose(float(logged_val), probe_val, rel_tol=0, abs_tol=1e-12)
    finally:
        terminate(process)
        stop_port_9090()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
