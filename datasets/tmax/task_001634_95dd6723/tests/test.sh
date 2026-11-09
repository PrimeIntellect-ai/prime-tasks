#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import glob
import json
import os
import random
import re
import signal
import socket
import subprocess
import tempfile
import threading
import time
import urllib.request
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest

CJSON_DIR = "/app/cjson-1.7.15"
CJSON_SO = os.path.join(CJSON_DIR, "libcjson.so")
VALIDATOR = "/home/user/ci_validator"


def validator_env():
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = CJSON_DIR + ":" + env.get("LD_LIBRARY_PATH", "")
    return env


def run_validator(path, timeout=5):
    return subprocess.run(
        [VALIDATOR, path],
        env=validator_env(),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )


def test_01_cjson_compiled_and_valid():
    build = subprocess.run(
        ["make", "-B"], cwd=CJSON_DIR, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, text=True, timeout=60
    )
    assert build.returncode == 0, "Running make in the vendored cJSON directory failed:\n" + build.stdout
    assert os.path.isfile(CJSON_SO), f"Expected shared library {CJSON_SO} does not exist. Did you fix the Makefile and compile it?"
    with open(CJSON_SO, "rb") as f:
        assert f.read(4) == b"\x7fELF", "libcjson.so is not an ELF shared library"
    try:
        lib = ctypes.CDLL(CJSON_SO)
        version = lib.cJSON_Version
        version.restype = ctypes.c_char_p
        assert version(), "cJSON_Version returned no version"
    except Exception as exc:
        pytest.fail(f"libcjson.so could not be loaded or does not export cJSON symbols: {exc}")


def test_02_rest_api_running():
    url = "http://127.0.0.1:8080/limits"
    try:
        req = urllib.request.Request(url, method="GET")
        with urllib.request.urlopen(req, timeout=2) as response:
            assert response.status == 200, f"Expected HTTP 200, got {response.status}"
            data = json.loads(response.read().decode("utf-8"))
            assert data.get("max_cpu") == 100, f"Expected max_cpu=100, got {data.get('max_cpu')}"
            assert data.get("max_mem") == 200, f"Expected max_mem=200, got {data.get('max_mem')}"
    except Exception as exc:
        pytest.fail(f"Failed to connect to REST API at {url} or parse its response: {exc}")


def test_03_ci_validator_corpus_and_linkage():
    assert os.path.isfile(VALIDATOR), f"Validator binary {VALIDATOR} does not exist."
    assert os.access(VALIDATOR, os.X_OK), f"Validator binary {VALIDATOR} is not executable."
    with open(VALIDATOR, "rb") as f:
        assert f.read(4) == b"\x7fELF", "ci_validator must be a compiled executable"

    dynamic = subprocess.run(
        ["readelf", "-d", VALIDATOR], env=validator_env(),
        capture_output=True, text=True, timeout=5
    )
    assert dynamic.returncode == 0, "Could not inspect ci_validator dynamic linkage"
    assert re.search(r"Shared library: \[libcjson\.so(?:\.[^]]*)?\]", dynamic.stdout), \
        "ci_validator is not dynamically linked against libcjson.so"

    symbols = subprocess.run(
        ["nm", "-D", VALIDATOR], env=validator_env(),
        capture_output=True, text=True, timeout=5
    )
    assert symbols.returncode == 0, "Could not inspect ci_validator symbols"
    assert re.search(r"\bU\s+cJSON_Parse(?:WithLength(?:Opts)?)?(?:@|\s|$)", symbols.stdout, re.MULTILINE), \
        "ci_validator does not reference a cJSON parsing function"

    linked = subprocess.run(
        ["ldd", VALIDATOR], env=validator_env(), capture_output=True, text=True, timeout=5
    )
    assert linked.returncode == 0, "ldd failed for ci_validator"
    assert CJSON_DIR in linked.stdout and "libcjson.so" in linked.stdout, \
        "ci_validator does not resolve libcjson from the fixed vendored library"

    clean_dir = "/home/user/corpus/clean"
    evil_dir = "/home/user/corpus/evil"
    clean_files = glob.glob(os.path.join(clean_dir, "*.json"))
    evil_files = glob.glob(os.path.join(evil_dir, "*.json"))
    assert len(clean_files) > 0, "No clean corpus files found."
    assert len(evil_files) > 0, "No evil corpus files found."

    clean_failed = []
    for path in clean_files:
        if run_validator(path).returncode != 0:
            clean_failed.append(os.path.basename(path))

    evil_bypassed = []
    for path in evil_files:
        if run_validator(path).returncode == 0:
            evil_bypassed.append(os.path.basename(path))

    errors = []
    if clean_failed:
        errors.append(f"{len(clean_failed)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_failed)}")
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed (accepted): {', '.join(evil_bypassed)}")
    if errors:
        pytest.fail("Corpus validation failed: " + " | ".join(errors))


def listener_pids(port):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].split(":")[-1].upper() == wanted and fields[3] == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass
    pids = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError):
            pass
    return pids


def stop_existing_api():
    for sig in (signal.SIGTERM, signal.SIGKILL):
        pids = listener_pids(8080)
        if not pids:
            return
        for pid in pids:
            try:
                os.kill(pid, sig)
            except ProcessLookupError:
                pass
        time.sleep(0.4)
    assert not listener_pids(8080), "Could not replace the API for dynamic verification"


def derived_result(doc, max_cpu, max_mem):
    try:
        jobs = doc["jobs"]
        if not isinstance(jobs, list):
            return False
        names = []
        graph = {}
        total_cpu = 0
        total_mem = 0
        for job in jobs:
            name = job["name"]
            cpu = job["cpu"]
            mem = job["mem"]
            deps = job["depends_on"]
            if not isinstance(name, str) or not isinstance(cpu, int) or not isinstance(mem, int) or not isinstance(deps, list):
                return False
            if name in graph or any(not isinstance(dep, str) for dep in deps):
                return False
            names.append(name)
            graph[name] = deps
            total_cpu += cpu
            total_mem += mem
        if total_cpu > max_cpu or total_mem > max_mem:
            return False
        if any(dep not in graph for deps in graph.values() for dep in deps):
            return False
        state = {}
        def visit(node):
            if state.get(node) == 1:
                return False
            if state.get(node) == 2:
                return True
            state[node] = 1
            if any(not visit(dep) for dep in graph[node]):
                return False
            state[node] = 2
            return True
        return all(visit(name) for name in names)
    except (KeyError, TypeError):
        return False


def test_04_dynamic_inputs_and_live_limits():
    stop_existing_api()
    state = {"limits": {"max_cpu": 100, "max_mem": 200}, "requests": []}

    class LimitsHandler(BaseHTTPRequestHandler):
        def do_GET(self):
            state["requests"].append(self.path)
            if self.path != "/limits":
                self.send_response(404)
                self.end_headers()
                return
            body = json.dumps(state["limits"]).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Connection", "close")
            self.end_headers()
            self.wfile.write(body)
        def log_message(self, *args):
            pass

    ThreadingHTTPServer.allow_reuse_address = True
    server = ThreadingHTTPServer(("127.0.0.1", 8080), LimitsHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()

    rng = random.SystemRandom()
    max_cpu = rng.randint(53, 87)
    max_mem = rng.randint(91, 157)
    names = ["job_" + uuid.uuid4().hex for _ in range(4)]

    live_doc = {"jobs": [{"name": names[0], "cpu": max_cpu, "mem": max_mem, "depends_on": []}]}
    valid_dag = {"jobs": [
        {"name": names[2], "cpu": max_cpu // 3, "mem": max_mem // 3, "depends_on": [names[1]]},
        {"name": names[0], "cpu": max_cpu // 3, "mem": max_mem // 3, "depends_on": []},
        {"name": names[1], "cpu": max_cpu - 2 * (max_cpu // 3), "mem": max_mem - 2 * (max_mem // 3), "depends_on": [names[0]]},
    ]}
    cpu_over = {"jobs": [{"name": names[0], "cpu": max_cpu + rng.randint(1, 9), "mem": 1, "depends_on": []}]}
    mem_over = {"jobs": [{"name": names[0], "cpu": 1, "mem": max_mem + rng.randint(1, 9), "depends_on": []}]}
    cycle = {"jobs": [
        {"name": names[0], "cpu": 1, "mem": 1, "depends_on": [names[1]]},
        {"name": names[1], "cpu": 1, "mem": 1, "depends_on": [names[2]]},
        {"name": names[2], "cpu": 1, "mem": 1, "depends_on": [names[0]]},
    ]}
    self_cycle = {"jobs": [{"name": names[3], "cpu": 1, "mem": 1, "depends_on": [names[3]]}]}

    with tempfile.TemporaryDirectory(prefix="validator_dynamic_") as root:
        def check_doc(doc, limits):
            state["limits"] = {"max_cpu": limits[0], "max_mem": limits[1]}
            path = os.path.join(root, uuid.uuid4().hex + ".json")
            with open(path, "w") as f:
                json.dump(doc, f, separators=(",", ":"))
            before = len(state["requests"])
            result = run_validator(path)
            assert len(state["requests"]) > before, f"ci_validator did not fetch /limits for {path}"
            assert all(p == "/limits" for p in state["requests"][before:]), "ci_validator requested the wrong API path"
            expected = derived_result(doc, limits[0], limits[1])
            assert (result.returncode == 0) == expected, \
                f"Dynamic validation mismatch (expected {'accept' if expected else 'reject'}, rc={result.returncode}, stderr={result.stderr!r})"

        # The identical pipeline must change result when the live API limit changes.
        check_doc(live_doc, (max_cpu - 1, max_mem))
        check_doc(live_doc, (max_cpu, max_mem))
        check_doc(live_doc, (max_cpu, max_mem - 1))
        check_doc(valid_dag, (max_cpu, max_mem))
        check_doc(cpu_over, (max_cpu, max_mem))
        check_doc(mem_over, (max_cpu, max_mem))
        check_doc(cycle, (max_cpu, max_mem))
        check_doc(self_cycle, (max_cpu, max_mem))

        malformed = os.path.join(root, uuid.uuid4().hex + ".json")
        with open(malformed, "w") as f:
            f.write('{"jobs":[{"name":"broken",')
        state["limits"] = {"max_cpu": max_cpu, "max_mem": max_mem}
        before = len(state["requests"])
        result = run_validator(malformed)
        assert len(state["requests"]) > before, "ci_validator did not fetch /limits for malformed input"
        assert result.returncode != 0, "Malformed JSON was accepted"

        missing = os.path.join(root, uuid.uuid4().hex + ".json")
        before = len(state["requests"])
        result = run_validator(missing)
        assert len(state["requests"]) > before, "ci_validator did not fetch /limits for a missing input file"
        assert result.returncode != 0, "A nonexistent pipeline file was accepted"

    server.shutdown()
    server.server_close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
