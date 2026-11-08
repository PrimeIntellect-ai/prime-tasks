#!/bin/bash
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import json
import socket
import urllib.request
import pytest
import math
import secrets
import time

BASE_URL = "http://127.0.0.1:8080"


def reset_server():
    req = urllib.request.Request(BASE_URL + "/reset", method="GET")
    with urllib.request.urlopen(req, timeout=2) as response:
        assert response.status == 200, "Failed to reset server state."


def send_metric(value):
    payload = json.dumps({"value": value}).encode("utf-8")
    req = urllib.request.Request(BASE_URL + "/metric", data=payload, method="POST")
    req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req, timeout=2) as response:
        assert response.status == 200, "Failed to send metric."
        data = json.loads(response.read().decode("utf-8"))
    assert "variance" in data, "Server response is missing variance."
    variance = data["variance"]
    assert isinstance(variance, (int, float)) and not isinstance(variance, bool)
    assert math.isfinite(variance), f"Server returned non-finite variance {variance}."
    return float(variance)


def welford_states(values):
    count = 0
    mean = 0.0
    m2 = 0.0
    states = []
    for value in values:
        count += 1
        delta = value - mean
        mean += delta / float(count)
        delta2 = value - mean
        m2 += delta * delta2
        variance = m2 / float(count)
        states.append((count, mean, m2, variance))
    return states


def test_source_contains_welford_implementation():
    path = "/home/user/aggregator/main.go"
    assert os.path.isfile(path) and not os.path.islink(path), f"{path} must be a regular Go source file."
    with open(path, "r", encoding="utf-8") as f:
        source = f.read()
    lowered = source.lower()
    assert re.search(r"\bpackage\s+main\b", source), "main.go is not a Go main package."
    assert re.search(r"\bm2\b", lowered), "main.go does not contain Welford's M2 state."
    assert re.search(r"\bmean\b", lowered), "main.go does not contain running mean state."
    assert re.search(r"\bdelta\w*\b", lowered), "main.go does not contain Welford delta calculations."
    assert "trace.log" in source, "main.go does not write the required trace log."
    assert "%f" in source, "main.go does not use the required floating-point trace format."


def test_mre_json():
    path = "/home/user/mre.json"
    assert os.path.isfile(path), f"File {path} is missing."

    with open(path, "r") as f:
        try:
            mre_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {path} is not valid JSON.")

    assert isinstance(mre_data, list), f"Expected {path} to contain a JSON array."
    expected_mre = [10000000000.0, 10000000000.1, 10000000000.2]
    assert mre_data == expected_mre, f"MRE sequence in {path} does not match the expected minimal sequence."


def test_resolution_json():
    path = "/home/user/resolution.json"
    assert os.path.isfile(path), f"File {path} is missing."

    with open(path, "r") as f:
        try:
            res_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {path} is not valid JSON.")

    assert "variance" in res_data, f"'variance' key missing in {path}."
    variance = res_data["variance"]
    assert isinstance(variance, (int, float)), f"'variance' is not a number in {path}."

    expected_variance = 0.006666666666666667
    assert math.isclose(variance, expected_variance, rel_tol=1e-3, abs_tol=1e-5), \
        f"Variance {variance} in {path} is incorrect. Expected approximately {expected_variance}."


def test_trace_log():
    path = "/home/user/trace.log"
    assert os.path.isfile(path), f"File {path} is missing."

    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) >= 3, f"Expected at least 3 lines in {path}."
    last_3_lines = lines[-3:]
    expected_patterns = ["Count: 1", "Count: 2", "Count: 3"]

    for i, pattern in enumerate(expected_patterns):
        assert pattern in last_3_lines[i], f"Expected '{pattern}' in log line: {last_3_lines[i]}"

    last_line = last_3_lines[-1]
    assert "Mean:" in last_line, f"Missing 'Mean:' in log line: {last_line}"
    assert "M2:" in last_line, f"Missing 'M2:' in log line: {last_line}"
    assert "Variance:" in last_line, f"Missing 'Variance:' in log line: {last_line}"


def test_server_running_and_fixed():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        result = s.connect_ex(("127.0.0.1", 8080))
        assert result == 0, "Server is not listening on port 8080."

    try:
        reset_server()
    except Exception as e:
        pytest.fail(f"Could not reach /reset endpoint: {e}")

    mre_sequence = [10000000000.0, 10000000000.1, 10000000000.2]
    last_variance = None
    for val in mre_sequence:
        try:
            last_variance = send_metric(val)
        except Exception as e:
            pytest.fail(f"Could not send metric to server: {e}")

    assert last_variance is not None, "Server did not return a variance."
    expected_variance = 0.006666666666666667
    assert math.isclose(last_variance, expected_variance, rel_tol=1e-3, abs_tol=1e-5), \
        f"Server returned incorrect variance {last_variance}. Expected approximately {expected_variance}."


def test_dynamic_streams_and_exact_trace_states():
    rng = secrets.SystemRandom()
    large_base = rng.uniform(1.0e9, 1.0e12)
    negative_base = -rng.uniform(1.0e8, 1.0e11)
    streams = [
        [large_base + rng.uniform(-250.0, 250.0) for _ in range(8)],
        [rng.uniform(-1.0e6, 1.0e6) for _ in range(9)],
        [negative_base + rng.uniform(-20.0, 20.0) for _ in range(7)],
    ]

    trace_path = "/home/user/trace.log"
    assert os.path.isfile(trace_path), f"File {trace_path} is missing."
    start_size = os.path.getsize(trace_path)
    expected_trace_states = []

    for stream in streams:
        reset_server()
        states = welford_states(stream)
        expected_trace_states.extend(states)
        for value, state in zip(stream, states):
            actual = send_metric(value)
            expected = state[3]
            assert actual >= -1e-12, f"Variance became negative: {actual}."
            assert math.isclose(actual, expected, rel_tol=1e-9, abs_tol=1e-7), \
                f"For dynamic stream prefix, server returned {actual}; expected {expected}."

    time.sleep(0.1)
    with open(trace_path, "r", encoding="utf-8") as f:
        f.seek(start_size)
        new_lines = [line.rstrip("\n") for line in f if line.strip()]

    assert len(new_lines) == len(expected_trace_states), \
        "The server must append exactly one trace line after every processed value."

    pattern = re.compile(
        r"^Count: (\d+), Mean: ([-+]?\d+\.\d{6}), "
        r"M2: ([-+]?\d+\.\d{6}), Variance: ([-+]?\d+\.\d{6})$"
    )
    for line, expected in zip(new_lines, expected_trace_states):
        match = pattern.fullmatch(line)
        assert match, f"Trace line does not have the required exact %f format: {line!r}"
        count = int(match.group(1))
        mean, m2, variance = map(float, match.groups()[1:])
        exp_count, exp_mean, exp_m2, exp_variance = expected
        assert count == exp_count, f"Trace count {count} should be {exp_count}."
        assert math.isclose(mean, exp_mean, rel_tol=0.0, abs_tol=1e-6), \
            f"Traced mean {mean} should be {exp_mean}."
        assert math.isclose(m2, exp_m2, rel_tol=0.0, abs_tol=1e-6), \
            f"Traced M2 {m2} should be {exp_m2}."
        assert math.isclose(variance, exp_variance, rel_tol=0.0, abs_tol=1e-6), \
            f"Traced variance {variance} should be {exp_variance}."
TEST_EOF

# Stop whichever process the agent left listening on 8080. The submitted source is
# then built and executed directly, so an unrelated fake listener cannot be tested.
python3 << 'PY'
import os
import signal
import time

inodes = set()
for table in ("/proc/net/tcp", "/proc/net/tcp6"):
    try:
        with open(table) as f:
            next(f, None)
            for line in f:
                fields = line.split()
                if len(fields) > 9 and fields[1].rsplit(":", 1)[-1].upper() == "1F90":
                    inodes.add(fields[9])
    except OSError:
        pass

for entry in os.listdir("/proc"):
    if not entry.isdigit() or int(entry) == os.getpid():
        continue
    fd_dir = f"/proc/{entry}/fd"
    try:
        for fd in os.listdir(fd_dir):
            try:
                target = os.readlink(f"{fd_dir}/{fd}")
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                try:
                    os.kill(int(entry), signal.SIGKILL)
                except (ProcessLookupError, PermissionError):
                    pass
                break
    except OSError:
        pass
time.sleep(0.2)
PY

if ! cd /home/user/aggregator || ! go build -o /tmp/submitted-aggregator main.go; then
    exit 0
fi

nohup /tmp/submitted-aggregator >/tmp/submitted-aggregator.out 2>&1 &
echo $! > /tmp/submitted-aggregator.pid

if ! python3 << 'PY'
import socket
import time
for _ in range(50):
    try:
        with socket.create_connection(("127.0.0.1", 8080), timeout=0.2):
            raise SystemExit(0)
    except OSError:
        time.sleep(0.1)
raise SystemExit(1)
PY
then
    exit 0
fi

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
