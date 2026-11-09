#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import random
import re
import signal
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.request

import pytest

BASE_DIR = "/home/user/telemetry-system"
URL = "http://127.0.0.1:8080/api/process"


def post_status(url, payload, timeout=3):
    data = json.dumps(payload, separators=(",", ":")).encode()
    req = urllib.request.Request(
        url, data=data, headers={"Content-Type": "application/json"}, method="POST"
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            return response.status
    except urllib.error.HTTPError as exc:
        return exc.code


def listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10:
                        local = fields[1]
                        state = fields[3]
                        if state == "0A" and int(local.rsplit(":", 1)[1], 16) == port:
                            inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
    for proc in glob.glob("/proc/[0-9]*"):
        pid = int(proc.rsplit("/", 1)[1])
        try:
            for fd in os.listdir(os.path.join(proc, "fd")):
                try:
                    target = os.readlink(os.path.join(proc, "fd", fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(pid)
        except (FileNotFoundError, PermissionError):
            pass
    return pids


def kill_service_ports():
    for _ in range(4):
        pids = set()
        for port in (8080, 9000, 9001):
            pids.update(listener_pids(port))
        for pid in pids:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        if not pids:
            break
        time.sleep(0.25)


def wait_for_port(port, timeout=20):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.25):
                return
        except OSError:
            time.sleep(0.1)
    pytest.fail(f"Port {port} did not become ready")


def oracle(a, b):
    if any(a[i] <= a[i - 1] for i in range(1, len(a))):
        return False
    if any(b[i] <= b[i - 1] for i in range(1, len(b))):
        return False
    merged = sorted(a + b)
    return all(merged[i] - merged[i - 1] <= 10 for i in range(1, len(merged)))


def generated_cases():
    rng = random.SystemRandom()
    cases = [
        ([], []),
        ([-5], []),
        ([1, 11], [1, 6]),
        ([-20, -10, 0], [-15, -5, 5]),
        ([0, 20], [10]),
        ([0, 21], [10]),
        ([1, 1], [2, 3]),
        ([1, 3], [5, 4]),
        ([7, 17, 27], [12, 22, 32]),
    ]

    for _ in range(35):
        count = rng.randint(2, 18)
        values = [rng.randint(-500, 500)]
        for _ in range(count - 1):
            values.append(values[-1] + rng.randint(1, 10))
        a, b = [], []
        for value in values:
            (a if rng.randrange(2) == 0 else b).append(value)
        cases.append((a, b))

    for _ in range(20):
        base = rng.randint(-1000, 1000)
        gap = rng.randint(11, 100)
        cases.append(([base - rng.randint(1, 10), base], [base + gap, base + gap + rng.randint(1, 10)]))

    for _ in range(20):
        values = sorted(rng.sample(range(-2000, 2000), rng.randint(3, 10)))
        a = values[::2]
        b = values[1::2]
        target = a if len(a) >= 2 else b
        target[rng.randrange(1, len(target))] = target[rng.randrange(0, len(target) - 1)]
        cases.append((a, b))
    return cases


def test_ci_script():
    ci_script = os.path.join(BASE_DIR, "ci.sh")
    assert os.path.isfile(ci_script), f"Missing CI script at {ci_script}"

    result = subprocess.run(["bash", ci_script], capture_output=True, text=True, timeout=90)
    assert result.returncode == 0, f"ci.sh failed with exit code {result.returncode}. Output:\n{result.stdout}\n{result.stderr}"
    assert result.stdout == "CI PASS\n", f"ci.sh must print exactly 'CI PASS'. Output:\n{result.stdout}"


def test_adversarial_corpus():
    clean_dir = os.path.join(BASE_DIR, "corpus", "clean")
    evil_dir = os.path.join(BASE_DIR, "corpus", "evil")

    clean_files = glob.glob(os.path.join(clean_dir, "*.json"))
    evil_files = glob.glob(os.path.join(evil_dir, "*.json"))

    assert len(clean_files) > 0, "No clean corpus files found"
    assert len(evil_files) > 0, "No evil corpus files found"

    clean_failed = []
    evil_bypassed = []

    for c_file in clean_files:
        with open(c_file, "rb") as f:
            data = f.read()
        req = urllib.request.Request(URL, data=data, headers={"Content-Type": "application/json"}, method="POST")
        try:
            with urllib.request.urlopen(req) as response:
                if response.status != 200:
                    clean_failed.append(os.path.basename(c_file))
        except urllib.error.HTTPError:
            clean_failed.append(os.path.basename(c_file))
        except urllib.error.URLError as e:
            pytest.fail(f"Failed to connect to {URL}: {e}")

    for e_file in evil_files:
        with open(e_file, "rb") as f:
            data = f.read()
        req = urllib.request.Request(URL, data=data, headers={"Content-Type": "application/json"}, method="POST")
        try:
            with urllib.request.urlopen(req) as response:
                if response.status == 200:
                    evil_bypassed.append(os.path.basename(e_file))
        except urllib.error.HTTPError as e:
            if e.code != 400:
                evil_bypassed.append(os.path.basename(e_file))
        except urllib.error.URLError as e:
            pytest.fail(f"Failed to connect to {URL}: {e}")

    errors = []
    if clean_failed:
        errors.append(f"{len(clean_failed)} of {len(clean_files)} clean modified: {', '.join(clean_failed)}")
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if errors:
        pytest.fail(" | ".join(errors))


def test_sources_build_and_validator_algorithm():
    required = ["worker.cpp", "main.go", "validator.go", "start_services.sh", "nginx.conf"]
    for name in required:
        assert os.path.isfile(os.path.join(BASE_DIR, name)), f"Missing required artifact: {name}"

    cases = generated_cases()
    encoded = [{"a": a, "b": b} for a, b in cases]
    expected = [oracle(a, b) for a, b in cases]

    with tempfile.TemporaryDirectory() as td:
        worker_out = os.path.join(td, "worker-check")
        backend_out = os.path.join(td, "backend-check")
        subprocess.run(
            ["g++", os.path.join(BASE_DIR, "worker.cpp"), "-o", worker_out],
            check=True, capture_output=True, text=True,
        )
        subprocess.run(
            ["go", "build", "-o", backend_out, os.path.join(BASE_DIR, "main.go"), os.path.join(BASE_DIR, "validator.go")],
            check=True, capture_output=True, text=True,
        )

        validator_copy = os.path.join(td, "validator.go")
        with open(os.path.join(BASE_DIR, "validator.go")) as src, open(validator_copy, "w") as dst:
            dst.write(src.read())
        harness = os.path.join(td, "validator_harness.go")
        with open(harness, "w") as f:
            f.write(r'''package main
import ("encoding/json"; "fmt"; "os")
type verifierCase struct { A []int `json:"a"`; B []int `json:"b"` }
func main() {
    var cs []verifierCase
    if err := json.NewDecoder(os.Stdin).Decode(&cs); err != nil { panic(err) }
    out := make([]bool, len(cs))
    for i, c := range cs { out[i] = ValidateTelemetry(c.A, c.B) }
    if err := json.NewEncoder(os.Stdout).Encode(out); err != nil { panic(err) }
    fmt.Fprint(os.Stderr, "")
}
''')
        validator_bin = os.path.join(td, "validator-check")
        subprocess.run(["go", "build", "-o", validator_bin, harness, validator_copy], check=True, capture_output=True, text=True)
        result = subprocess.run(
            [validator_bin], input=json.dumps(encoded), capture_output=True, text=True, check=True, timeout=15
        )
        actual = json.loads(result.stdout)
        assert actual == expected, "ValidateTelemetry does not implement strict monotonicity and merged adjacent-gap validation"


def test_nginx_configuration_and_real_orchestration():
    nginx_conf = os.path.join(BASE_DIR, "nginx.conf")
    checked = subprocess.run(
        ["nginx", "-T", "-p", BASE_DIR + "/", "-c", nginx_conf],
        capture_output=True, text=True,
    )
    assert checked.returncode == 0, f"Invalid nginx.conf:\n{checked.stdout}\n{checked.stderr}"
    rendered = checked.stdout + "\n" + checked.stderr
    rendered = "\n".join(line.split("#", 1)[0] for line in rendered.splitlines())
    assert re.search(r"\blisten\s+[^;]*\b8080\b[^;]*;", rendered), "nginx.conf does not listen on port 8080"
    assert re.search(
        r"location\s+(?:\^~\s+)?/api/\s*\{[^{}]*proxy_pass\s+http://127\.0\.0\.1:9000\s*;",
        rendered, re.S,
    ), "nginx.conf must proxy /api/ to http://127.0.0.1:9000"

    kill_service_ports()
    for name in ("worker", "backend"):
        path = os.path.join(BASE_DIR, name)
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    starter = subprocess.Popen(
        ["bash", os.path.join(BASE_DIR, "start_services.sh")],
        cwd=BASE_DIR, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    try:
        for port in (9001, 9000, 8080):
            wait_for_port(port)

        worker_path = os.path.join(BASE_DIR, "worker")
        backend_path = os.path.join(BASE_DIR, "backend")
        assert os.path.isfile(worker_path) and os.access(worker_path, os.X_OK), "start_services.sh did not compile worker"
        assert os.path.isfile(backend_path) and os.access(backend_path, os.X_OK), "start_services.sh did not build backend"

        worker_pids = listener_pids(9001)
        backend_pids = listener_pids(9000)
        nginx_pids = listener_pids(8080)
        assert worker_pids, "No C++ worker is listening on port 9001"
        assert backend_pids, "No Go backend is listening on port 9000"
        assert nginx_pids, "No Nginx process is listening on port 8080"
        assert any(os.path.samefile(f"/proc/{pid}/exe", worker_path) for pid in worker_pids), "Port 9001 is not served by the compiled worker"
        assert any(os.path.samefile(f"/proc/{pid}/exe", backend_path) for pid in backend_pids), "Port 9000 is not served by the built backend"
        assert any("nginx" in os.path.basename(os.readlink(f"/proc/{pid}/exe")) for pid in nginx_pids), "Port 8080 is not served by Nginx"

        with urllib.request.urlopen("http://127.0.0.1:9001", timeout=3) as response:
            assert response.status == 200, "Compiled C++ worker did not respond on port 9001"

        for a, b in generated_cases()[:35]:
            expected = 200 if oracle(a, b) else 400
            payload = {"series_a": a, "series_b": b}
            assert post_status("http://127.0.0.1:9000/api/process", payload) == expected, "Go backend returned the wrong status"
            assert post_status(URL, payload) == expected, "Nginx proxy path returned the wrong status"
    finally:
        if starter.poll() is None:
            starter.kill()
        kill_service_ports()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
