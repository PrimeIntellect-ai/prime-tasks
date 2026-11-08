#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import math
import os
import random
import re
import socket
import subprocess
import time
import urllib.request

import pytest

ROOT = "/app/bayesian_tracker-1.0.0"
URL = "http://127.0.0.1:8080/sample"


def post(payload):
    request = urllib.request.Request(
        URL,
        data=payload.encode("ascii"),
        method="POST",
        headers={"Content-Type": "text/plain"},
    )
    with urllib.request.urlopen(request, timeout=5) as response:
        return response.status, response.headers.get("Content-Type", ""), response.read().decode().strip()


def wait_for_server():
    deadline = time.time() + 5
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", 8080), timeout=1):
                return
        except OSError:
            time.sleep(0.2)
    pytest.fail("Server is not listening on 127.0.0.1:8080")


def listener_pid():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local, state, inode = fields[1], fields[3], fields[9]
                    if int(local.rsplit(":", 1)[1], 16) == 8080 and state == "0A":
                        inodes.add(inode)
        except FileNotFoundError:
            pass

    for proc in glob.glob("/proc/[0-9]*"):
        for fd in glob.glob(proc + "/fd/*"):
            try:
                target = os.readlink(fd)
            except OSError:
                continue
            match = re.fullmatch(r"socket:\[(\d+)\]", target)
            if match and match.group(1) in inodes:
                return int(proc.rsplit("/", 1)[1])
    return None


def test_requested_library_files_and_clean_build():
    makefile_path = os.path.join(ROOT, "Makefile")
    source_path = os.path.join(ROOT, "src/update_engine.cpp")
    assert os.path.isfile(makefile_path)
    assert os.path.isfile(source_path)

    makefile = open(makefile_path).read()
    assert "CXX_COMPILER" not in makefile, "Makefile still uses the nonstandard CXX_COMPILER variable"
    assert re.search(r"\$\([ \t]*CXX[ \t]*\)|\$\{[ \t]*CXX[ \t]*\}", makefile), "Makefile does not invoke CXX"

    source = open(source_path).read()
    assert "-9999" in source, "update_engine.cpp does not handle the sentinel"
    assert not re.search(r"\bNAN\b|quiet_NaN|signaling_NaN", source), "Sentinels are still converted into NaNs"

    subprocess.run(["make", "clean"], cwd=ROOT, check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    build = subprocess.run(
        ["make", "CXX=g++"], cwd=ROOT, check=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True
    )
    assert os.path.isfile(os.path.join(ROOT, "libtracker.a")), build.stdout


def test_fresh_library_handles_derived_inputs(tmp_path):
    harness = tmp_path / "library_harness.cpp"
    executable = tmp_path / "library_harness"
    harness.write_text(r'''#include "tracker.h"
#include <iostream>
#include <vector>
int main() {
    int n;
    while (std::cin >> n) {
        std::vector<int> values;
        for (int i = 0; i < n; ++i) {
            int value;
            if (!(std::cin >> value)) return 2;
            values.push_back(value);
        }
        std::cout << Tracker::compute_mean(values) << "\n";
    }
    return 0;
}
''')
    subprocess.run([
        "g++", "-std=c++11", "-I" + os.path.join(ROOT, "include"),
        str(harness), os.path.join(ROOT, "libtracker.a"), "-o", str(executable)
    ], check=True)

    rng = random.SystemRandom()
    vectors = [[], [-9999], [-9999, -9999, -9999]]
    for _ in range(20):
        values = [rng.randint(-500, 500) for _ in range(rng.randint(2, 18))]
        for _ in range(rng.randint(1, min(5, len(values)))):
            values[rng.randrange(len(values))] = -9999
        vectors.append(values)

    stdin = "".join(str(len(v)) + (" " + " ".join(map(str, v)) if v else "") + "\n" for v in vectors)
    result = subprocess.run([str(executable)], input=stdin, text=True, check=True, stdout=subprocess.PIPE)
    outputs = result.stdout.splitlines()
    assert len(outputs) == len(vectors)
    for values, output in zip(vectors, outputs):
        kept = [v for v in values if v != -9999]
        expected = sum(kept) / len(kept) if kept else 0.0
        actual = float(output)
        assert math.isfinite(actual)
        assert actual == pytest.approx(expected, abs=1e-4)


def test_server_log_exists():
    log_path = "/home/user/server.log"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist."
    with open(log_path) as f:
        content = f.read()
    assert "Server started on port 8080" in content


def test_running_server_is_cpp_and_uses_tracker():
    wait_for_server()
    pid = listener_pid()
    assert pid is not None, "Could not identify the process listening on port 8080"
    exe = f"/proc/{pid}/exe"
    with open(exe, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The listening server is not a compiled executable"
    symbols = subprocess.run(["nm", "-C", exe], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT).stdout
    assert "Tracker::compute_mean" in symbols, "The running server executable is not linked to Tracker::compute_mean"

    candidates = []
    for root in ("/app", "/home/user"):
        for extension in ("*.cpp", "*.cc", "*.cxx"):
            candidates.extend(glob.glob(root + "/**/" + extension, recursive=True))
    candidates = [p for p in candidates if os.path.realpath(p) != os.path.realpath(os.path.join(ROOT, "src/update_engine.cpp"))]
    found = False
    for path in candidates:
        try:
            text = open(path, errors="ignore").read()
        except OSError:
            continue
        if "httplib" in text and "/sample" in text and "Tracker::compute_mean" in text:
            found = True
            break
    assert found, "No C++ httplib server source using Tracker::compute_mean was found"


def test_http_server_sample_endpoint():
    status, content_type, body = post("10,20,-9999,30")
    assert status == 200
    assert content_type.lower().startswith("text/plain")
    assert float(body) == 20.0


def test_http_server_multiple_sentinels():
    status, _, body = post("-9999,5,15,-9999,25,-9999")
    assert status == 200
    assert float(body) == 15.0


def test_http_server_on_runtime_generated_payloads():
    rng = random.SystemRandom()
    for _ in range(20):
        values = [rng.randint(-1000, 1000) for _ in range(rng.randint(3, 20))]
        for _ in range(rng.randint(1, min(6, len(values)))):
            values[rng.randrange(len(values))] = -9999
        kept = [v for v in values if v != -9999]
        expected = sum(kept) / len(kept) if kept else 0.0
        status, content_type, body = post(",".join(map(str, values)))
        assert status == 200
        assert content_type.lower().startswith("text/plain")
        actual = float(body)
        assert math.isfinite(actual)
        assert actual == pytest.approx(expected, abs=1e-4)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
