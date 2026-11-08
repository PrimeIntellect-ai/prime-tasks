#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import stat
import subprocess
import time

import requests

MODEL = "/home/user/model.sh"
REGRESSION = "/home/user/test_model.sh"
TARGETS = [39, 63, 78, 86, 92]
K1_GRID = list(range(10, 51, 5))
K2_GRID = [i / 10 for i in range(1, 11)]


def reference_model(k1, k2):
    m = 0.0
    values = []
    for step in range(1, 51):
        m += 0.1 * (k1 - k2 * m)
        if step % 10 == 0:
            values.append(math.floor(m + 0.5))
    return values


def run_model(k1, k2):
    result = subprocess.run(
        [MODEL, str(k1), str(k2)],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"model.sh failed for ({k1}, {k2}) with exit code "
        f"{result.returncode}:\n{result.stderr}"
    )
    lines = result.stdout.splitlines()
    assert len(lines) == 5, f"Expected exactly five output lines, got: {result.stdout!r}"
    assert all(re.fullmatch(r"-?[0-9]+", line) for line in lines), (
        f"Every model output line must be an integer: {result.stdout!r}"
    )
    return [int(line) for line in lines]


def optimum_from_reference():
    scored = []
    for k1 in K1_GRID:
        for k2 in K2_GRID:
            simulated = reference_model(k1, k2)
            sse = sum((actual - target) ** 2 for actual, target in zip(simulated, TARGETS))
            scored.append((sse, k1, k2))
    return min(scored)


def test_model_script_exists_executable_and_simulates_euler():
    assert os.path.exists(MODEL), f"Missing script: {MODEL}"
    assert os.access(MODEL, os.X_OK), f"Script is not executable: {MODEL}"

    # Exercise both the required regression parameters and independent inputs.
    for k1, k2 in [(10, 0.5), (25, 0.3), (45, 0.8), (17, 0.65)]:
        assert run_model(k1, k2) == reference_model(k1, k2), (
            f"Incorrect Euler simulation for k1={k1}, k2={k2}"
        )


def test_regression_script_exists_passes_and_detects_bad_model():
    assert os.path.exists(REGRESSION), f"Missing script: {REGRESSION}"
    assert os.access(REGRESSION, os.X_OK), f"Script is not executable: {REGRESSION}"

    result = subprocess.run([REGRESSION], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, (
        f"test_model.sh failed with exit code {result.returncode}:\n{result.stderr}"
    )

    # A regression test that merely exits zero must not pass. Temporarily provide
    # a valid executable with deliberately wrong output and require rejection.
    original = open(MODEL, "rb").read()
    original_mode = stat.S_IMODE(os.stat(MODEL).st_mode)
    try:
        with open(MODEL, "wb") as f:
            f.write(b"#!/bin/bash\nprintf '1\\n2\\n3\\n4\\n5\\n'\n")
        os.chmod(MODEL, original_mode | stat.S_IXUSR)
        bad = subprocess.run([REGRESSION], capture_output=True, text=True, timeout=10)
        assert bad.returncode != 0, "test_model.sh accepted deliberately incorrect model output"
    finally:
        with open(MODEL, "wb") as f:
            f.write(original)
        os.chmod(MODEL, original_mode)


def ordered_numbers(text, values):
    pattern = r"(?<![0-9.])" + r"(?![0-9.]).*?(?<![0-9.])".join(
        re.escape(str(v)) for v in values
    ) + r"(?![0-9.])"
    return re.search(pattern, text, re.S) is not None


def test_pipeline_contains_transcription_parallel_grid_and_sse():
    chunks = []
    for root, _, files in os.walk("/home/user"):
        for name in files:
            path = os.path.join(root, name)
            try:
                if os.path.getsize(path) <= 1024 * 1024:
                    with open(path, "rb") as f:
                        chunks.append(f.read().decode("utf-8", "ignore"))
            except OSError:
                pass
    evidence = "\n".join(chunks)
    lower = evidence.lower()

    assert ordered_numbers(evidence, TARGETS), (
        "No pipeline artifact contains the five transcribed target values in order"
    )
    assert re.search(r"(^|[;&|\n])\s*(?:command\s+)?parallel(?:\s|$)", evidence, re.M), (
        "No GNU parallel invocation was found in the pipeline artifacts"
    )

    k1_explicit = ordered_numbers(evidence, K1_GRID)
    k1_generated = bool(re.search(r"(?:seq\s+10\s+5\s+50|\{10\.\.50\.\.5\})", evidence))
    assert k1_explicit or k1_generated, "The required k1 grid was not found"

    k2_strings = [f"{i / 10:.1f}" for i in range(1, 11)]
    k2_explicit = ordered_numbers(evidence, k2_strings)
    k2_generated = bool(re.search(r"seq\s+0?\.1\s+0?\.1\s+1(?:\.0)?", evidence))
    k2_integer_loop = bool(re.search(r"seq\s+1\s+(?:1\s+)?10", evidence) and re.search(r"/\s*10", evidence))
    assert k2_explicit or k2_generated or k2_integer_loop, "The required k2 grid was not found"

    assert "model.sh" in evidence, "The optimization pipeline does not invoke model.sh"
    assert re.search(r"\bsse\b", lower), "No SSE computation was found in the pipeline artifacts"
    assert re.search(r"(?:\*\s*[^\n;]*\*|\*\*|\^\s*2)", evidence), (
        "No squared-error arithmetic was found in the pipeline artifacts"
    )


def listening_ipv4_pids(port):
    wanted = f"{port:04X}"
    inodes = set()
    with open("/proc/net/tcp", "r") as f:
        for line in f.readlines()[1:]:
            fields = line.split()
            local_ip, local_port = fields[1].split(":")
            state = fields[3]
            if local_ip == "00000000" and local_port.upper() == wanted and state == "0A":
                inodes.add(fields[9])

    pids = set()
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[([0-9]+)\]", target)
                if match and match.group(1) in inodes:
                    pids.add(int(pid))
        except OSError:
            pass
    return pids


def test_http_server_result():
    expected_sse, expected_k1, expected_k2 = optimum_from_reference()
    assert (expected_k1, expected_k2) == (50, 0.5), (
        f"Reference grid-search result unexpectedly changed (SSE={expected_sse})"
    )

    pids = listening_ipv4_pids(8080)
    assert pids, "No server is listening on 0.0.0.0:8080"
    listener_names = set()
    for pid in pids:
        try:
            listener_names.add(os.path.basename(os.readlink(f"/proc/{pid}/exe")))
        except OSError:
            pass
    assert any(name in {"socat", "nc", "nc.openbsd", "netcat"} for name in listener_names), (
        f"Port 8080 is not being served with nc or socat; listeners were {listener_names}"
    )

    url = "http://127.0.0.1:8080/result"
    for request_number in range(3):
        response = None
        for attempt in range(3):
            try:
                response = requests.get(url, timeout=5)
                break
            except requests.exceptions.RequestException as exc:
                if attempt == 2:
                    raise AssertionError(f"Failed to connect to {url}: {exc}")
                time.sleep(1)

        assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}"
        try:
            data = response.json()
        except ValueError:
            raise AssertionError(f"Response body is not valid JSON: {response.text}")

        assert set(data) == {"k1", "k2"}, f"Unexpected JSON payload: {data}"
        assert data["k1"] == expected_k1, f"Expected k1={expected_k1}, got {data['k1']}"
        assert float(data["k2"]) == expected_k2, f"Expected k2={expected_k2}, got {data['k2']}"
        assert re.fullmatch(r"0\.5", str(data["k2"])), "k2 must be represented with one decimal place"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
