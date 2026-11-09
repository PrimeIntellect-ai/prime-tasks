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

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import importlib.metadata
import json
import os
import random
import re
import signal
import socket
import subprocess
import sys
import time
import uuid

import pytest
import requests

VENDOR = "/app/vendored/libdag-1.0.0"
BASE_URL = "http://127.0.0.1:8080"
TOKEN_HEADERS = {
    "Authorization": "Bearer ci-deploy-token-8842",
    "Content-Type": "application/json",
}
TRACE_DIR = "/tmp/libdag_trace_hook"
TRACE_FILE = "/tmp/libdag_calls.jsonl"


def wait_for_port(expected_open, timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        sock = socket.socket()
        sock.settimeout(0.2)
        try:
            opened = sock.connect_ex(("127.0.0.1", 8080)) == 0
        finally:
            sock.close()
        if opened == expected_open:
            return
        time.sleep(0.1)
    pytest.fail(f"port 127.0.0.1:8080 did not become {'open' if expected_open else 'closed'}")


def listener_pid():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = open(table).read().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) >= 10 and fields[1].split(":")[-1].upper() == "1F90" and fields[3] == "0A":
                inodes.add(fields[9])
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    return int(name)
        except OSError:
            pass
    pytest.fail("could not identify the process listening on 127.0.0.1:8080")


def restart_service_with_libdag_trace():
    wait_for_port(True)
    pid = listener_pid()
    try:
        raw_cmd = open(f"/proc/{pid}/cmdline", "rb").read().split(b"\0")
        argv = [part.decode(errors="surrogateescape") for part in raw_cmd if part]
        cwd = os.readlink(f"/proc/{pid}/cwd")
        raw_env = open(f"/proc/{pid}/environ", "rb").read().split(b"\0")
        env = {}
        for item in raw_env:
            if b"=" in item:
                key, value = item.split(b"=", 1)
                env[key.decode(errors="surrogateescape")] = value.decode(errors="surrogateescape")
    except OSError as exc:
        pytest.fail(f"unable to inspect running service process: {exc}")
    assert argv, "service process has an empty command line"

    os.makedirs(TRACE_DIR, exist_ok=True)
    try:
        os.unlink(TRACE_FILE)
    except FileNotFoundError:
        pass
    with open(os.path.join(TRACE_DIR, "sitecustomize.py"), "w") as handle:
        handle.write(r'''import json
import libdag
_path = getattr(libdag, "__file__", "")
_original_topological_sort = libdag.topological_sort
def _traced_topological_sort(graph, *args, **kwargs):
    with open("/tmp/libdag_calls.jsonl", "a") as out:
        out.write(json.dumps({"graph": graph, "module": _path}, sort_keys=True) + "\\n")
    return _original_topological_sort(graph, *args, **kwargs)
libdag.topological_sort = _traced_topological_sort
''')

    os.kill(pid, signal.SIGTERM)
    deadline = time.time() + 3
    while time.time() < deadline:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            break
        time.sleep(0.05)
    else:
        os.kill(pid, signal.SIGKILL)
    wait_for_port(False)

    old_pythonpath = env.get("PYTHONPATH", "")
    env["PYTHONPATH"] = TRACE_DIR + (os.pathsep + old_pythonpath if old_pythonpath else "")
    env["PYTHONUNBUFFERED"] = "1"
    with open("/tmp/restarted_service.out", "ab", buffering=0) as output:
        subprocess.Popen(argv, cwd=cwd, env=env, stdin=subprocess.DEVNULL,
                         stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
    wait_for_port(True)


def test_makefile_builds_real_linked_shared_libraries():
    assert os.path.isfile(os.path.join(VENDOR, "Makefile")), "vendored Makefile is missing"
    for name in ("libutils.so", "libcore.so"):
        try:
            os.unlink(os.path.join(VENDOR, name))
        except FileNotFoundError:
            pass
    result = subprocess.run(["make"], cwd=VENDOR, text=True, capture_output=True)
    assert result.returncode == 0, f"vendored make still fails:\n{result.stdout}\n{result.stderr}"

    for name in ("libutils.so", "libcore.so"):
        path = os.path.join(VENDOR, name)
        assert os.path.isfile(path), f"make did not create {name}"
        file_result = subprocess.run(["file", path], text=True, capture_output=True, check=True)
        assert "ELF" in file_result.stdout and "shared object" in file_result.stdout, file_result.stdout

    dynamic = subprocess.run(["readelf", "-d", os.path.join(VENDOR, "libcore.so")],
                             text=True, capture_output=True, check=True).stdout
    assert re.search(r"NEEDED.*libutils\.so", dynamic), "libcore.so is not linked against libutils.so"

    probe = subprocess.run(
        [sys.executable, "-c", "import ctypes; x=ctypes.CDLL('./libcore.so'); x.core_func()"],
        cwd=VENDOR,
        env={**os.environ, "LD_LIBRARY_PATH": VENDOR},
        text=True,
        capture_output=True,
    )
    assert probe.returncode == 0, f"linked libraries cannot be loaded and called: {probe.stderr}"


def test_libdag_installed_in_system_environment():
    probe_env = dict(os.environ)
    probe_env.pop("PYTHONPATH", None)
    code = "import json,libdag; print(json.dumps({'path':libdag.__file__,'has':hasattr(libdag,'topological_sort'),'result':libdag.topological_sort({'x':['y'],'y':[]})}))"
    result = subprocess.run([sys.executable, "-c", code], cwd="/tmp", env=probe_env,
                            text=True, capture_output=True)
    assert result.returncode == 0, f"libdag is not installed in the system environment: {result.stderr}"
    info = json.loads(result.stdout.strip().splitlines()[-1])
    assert info["has"], "installed libdag is missing topological_sort"
    assert info["result"] == ["y", "x"], "installed topological_sort is not functional"
    assert not os.path.realpath(info["path"]).startswith(os.path.realpath(VENDOR) + os.sep), \
        "libdag is only importable from the vendored source tree, not installed"
    assert importlib.metadata.version("libdag") == "1.0.0", "installed libdag distribution is missing or wrong version"


def post(path, payload, headers=TOKEN_HEADERS):
    try:
        return requests.post(BASE_URL + path, json=payload, headers=headers, timeout=5)
    except requests.RequestException as exc:
        pytest.fail(f"failed to connect to {BASE_URL + path}: {exc}")


def test_service_dynamic_behavior_rate_limit_auth_library_use_and_logging():
    restart_service_with_libdag_trace()

    log_path = "/home/user/service.log"
    deadline = time.time() + 3
    while time.time() < deadline and not os.path.isfile(log_path):
        time.sleep(0.05)
    assert os.path.isfile(log_path), f"log file {log_path} does not exist"
    log_offset = os.path.getsize(log_path)

    fixed_graph = {"A": ["B", "C"], "B": ["D"], "C": ["D"], "D": []}
    unauthorized = post("/resolve", {"graph": fixed_graph}, {
        "Authorization": "Bearer wrong-token", "Content-Type": "application/json"
    })
    assert unauthorized.status_code in (401, 403), "both endpoints must reject an invalid bearer token"

    # Authenticated request 1: retain the original fixed /resolve assertion.
    response = post("/resolve", {"graph": fixed_graph})
    assert response.status_code == 200, f"expected 200 for /resolve, got {response.status_code}: {response.text}"
    data = response.json()
    assert "build_order" in data, "missing build_order in response"
    assert data["build_order"] in (["D", "B", "C", "A"], ["D", "C", "B", "A"]), data

    # Authenticated request 2: retain the original fixed SemVer assertion.
    fixed_filter = {"versions": ["0.9.9", "1.2.4", "1.9.0", "2.0.1"],
                    "constraint": ">=1.0.0 <2.0.0"}
    response = post("/filter_versions", fixed_filter)
    assert response.status_code == 200, f"expected 200 for /filter_versions, got {response.status_code}: {response.text}"
    filtered = response.json()
    assert "compliant" in filtered, "missing compliant in response"
    assert sorted(filtered["compliant"]) == ["1.2.4", "1.9.0"], filtered

    # Authenticated requests 3 and 4: unpredictable, uniquely ordered graphs.
    dynamic_graphs = []
    for _ in range(2):
        labels = ["pkg_" + uuid.uuid4().hex for _ in range(5)]
        graph = {labels[i]: ([labels[i + 1]] if i + 1 < len(labels) else []) for i in range(len(labels))}
        items = list(graph.items())
        random.SystemRandom().shuffle(items)
        graph = dict(items)
        dynamic_graphs.append(graph)
        response = post("/resolve", {"graph": graph})
        assert response.status_code == 200, f"expected authenticated request to be 200, got {response.status_code}"
        assert response.json().get("build_order") == list(reversed(labels)), \
            f"incorrect dynamic build order: {response.text}"

    # Authenticated request 5: exercise SemVer prerelease numeric precedence.
    minor = random.SystemRandom().randrange(20, 90)
    prefix = f"1.{minor}.3"
    versions = [f"{prefix}-alpha.1", f"{prefix}-alpha.2", f"{prefix}-alpha.10",
                f"{prefix}-beta", prefix, f"1.{minor}.2", f"{prefix}+build.7"]
    semver_payload = {"versions": versions,
                      "constraint": f">={prefix}-alpha.2 <{prefix}"}
    expected_semver = [f"{prefix}-alpha.2", f"{prefix}-alpha.10", f"{prefix}-beta"]
    response = post("/filter_versions", semver_payload)
    assert response.status_code == 200, f"expected request 5 to be 200, got {response.status_code}"
    assert sorted(response.json().get("compliant", [])) == sorted(expected_semver), response.text

    # Authenticated request 6 must be rejected immediately.
    response = post("/filter_versions", semver_payload)
    assert response.status_code == 429, f"expected request 6 to be 429, got {response.status_code}"

    # The injected startup hook wraps the installed libdag function. Each successful
    # /resolve request must therefore produce a trace with the exact submitted graph.
    deadline = time.time() + 2
    while time.time() < deadline:
        if os.path.isfile(TRACE_FILE) and len(open(TRACE_FILE).read().splitlines()) >= 3:
            break
        time.sleep(0.05)
    assert os.path.isfile(TRACE_FILE), "/resolve did not call installed libdag.topological_sort"
    traces = [json.loads(line) for line in open(TRACE_FILE) if line.strip()]
    expected_graphs = [fixed_graph] + dynamic_graphs
    assert len(traces) == 3, f"expected one libdag call per successful /resolve request, got {len(traces)}"
    assert [entry["graph"] for entry in traces] == expected_graphs, \
        "/resolve did not pass the submitted graphs to libdag.topological_sort"
    for entry in traces:
        assert entry["module"] and not os.path.realpath(entry["module"]).startswith(os.path.realpath(VENDOR) + os.sep), \
            "service imported libdag from the vendored tree instead of the installed package"

    # Every request made above must be logged on a line containing its path and status.
    expected_logs = [
        ("/resolve", unauthorized.status_code),
        ("/resolve", 200), ("/filter_versions", 200),
        ("/resolve", 200), ("/resolve", 200),
        ("/filter_versions", 200), ("/filter_versions", 429),
    ]
    deadline = time.time() + 3
    new_text = ""
    while time.time() < deadline:
        with open(log_path, errors="replace") as handle:
            handle.seek(log_offset)
            new_text = handle.read()
        lines = [line for line in new_text.splitlines() if line.strip()]
        if len(lines) >= len(expected_logs):
            break
        time.sleep(0.1)
    assert new_text.strip(), "service log is empty"
    remaining = [line for line in new_text.splitlines() if line.strip()]
    for path, status in expected_logs:
        match_index = next((i for i, line in enumerate(remaining)
                            if path in line and re.search(rf"(?<!\d){status}(?!\d)", line)), None)
        assert match_index is not None, f"missing log entry containing request {path} and status {status}: {new_text!r}"
        remaining.pop(match_index)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
