#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_pipeline.py
import json
import math
import os
import re
import secrets
import stat
import subprocess
import time
import urllib.request

import numpy as np
import redis

PIPELINE = "/home/user/pipeline.sh"
SENSOR_DATA = "/tmp/verifier_sensor_data.json"
SENSOR_PROGRAM = "/app/sensor_sim.py"


def fail(message):
    raise AssertionError(message)


def check_pipeline_artifact():
    if not os.path.isfile(PIPELINE):
        fail(f"Missing required script: {PIPELINE}")
    mode = os.stat(PIPELINE).st_mode
    if not (mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)):
        fail(f"{PIPELINE} is not executable")

    with open(PIPELINE, "r", encoding="utf-8", errors="replace") as f:
        source = f.read()

    first_line = source.splitlines()[0] if source.splitlines() else ""
    if not re.match(r"^#!.*(?:/|\s)bash(?:\s|$)", first_line):
        fail("pipeline.sh must be a Bash script with a Bash shebang")
    if not re.search(r"\b(?:g?awk)\b", source):
        fail("pipeline.sh must use awk for statistical processing")
    if not re.search(r"\brand\s*\(", source):
        fail("pipeline.sh must use awk random resampling for bootstrap iterations")
    if not re.search(r"\b500\b", source):
        fail("pipeline.sh must specify exactly 500 bootstrap iterations")
    if not re.search(r"\bredis-cli\b", source):
        fail("pipeline.sh must export its JSON using redis-cli")

    # Python and R are explicitly forbidden for the processor.
    command_text = re.sub(r"#[^\n]*", "", source)
    forbidden = re.compile(
        r"(?:^|[\n;&|()]\s*)"
        r"(?:python(?:2|3)?|pypy(?:2|3)?|Rscript|R)"
        r"(?:\s|$)",
        re.MULTILINE,
    )
    if forbidden.search(command_text):
        fail("pipeline.sh may not invoke Python or R")


def install_controlled_sensor():
    program = r'''import json
import socket

HOST = "127.0.0.1"
PORT = 9001
DATA = "/tmp/verifier_sensor_data.json"

server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind((HOST, PORT))
server.listen(8)
while True:
    conn, _ = server.accept()
    try:
        with open(DATA, "r", encoding="utf-8") as f:
            rows = json.load(f)
        payload = "".join(",".join(f"{v:.2f}" for v in row) + "\\n" for row in rows)
        conn.sendall(payload.encode("ascii"))
    except (BrokenPipeError, ConnectionResetError):
        pass
    finally:
        conn.close()
'''
    with open(SENSOR_PROGRAM, "w", encoding="utf-8") as f:
        f.write(program)

    subprocess.run(["pkill", "-f", "/app/sensor_sim.py"], check=False)

    deadline = time.time() + 10
    target = "0100007F:2329"  # 127.0.0.1:9001 in /proc/net/tcp format
    while time.time() < deadline:
        try:
            with open("/proc/net/tcp", "r", encoding="ascii") as f:
                if any(target in line and line.split()[3] == "0A" for line in f.readlines()[1:]):
                    return
        except OSError:
            pass
        time.sleep(0.1)
    fail("Controlled sensor simulator did not start on port 9001")


def smooth_peaks(rows):
    peaks = []
    for row in rows:
        smoothed = [(row[0] + row[1]) / 2.0]
        smoothed.extend((row[i - 1] + row[i] + row[i + 1]) / 3.0 for i in range(1, 99))
        smoothed.append((row[98] + row[99]) / 2.0)
        peaks.append(max(smoothed))
    return np.asarray(peaks, dtype=float)


def expected_histogram(peaks):
    minimum = float(np.min(peaks))
    maximum = float(np.max(peaks))
    width = (maximum - minimum) / 5.0
    if width == 0:
        return [len(peaks), 0, 0, 0, 0]

    counts = [0] * 5
    for value in peaks:
        if value == maximum:
            index = 4
        elif value == minimum:
            index = 0
        else:
            # Boundaries belong to the lower bin.
            index = int(math.ceil((float(value) - minimum) / width) - 1)
            index = max(0, min(4, index))
        counts[index] += 1
    return counts


def bootstrap_reference(peaks):
    # Estimate the percentile-bootstrap population bounds independently. The
    # submitted implementation uses B=500, so its finite-sample percentile can
    # vary; tolerances below account for that sampling variation.
    rng = np.random.default_rng(913731)
    means = []
    for _ in range(30):
        indices = rng.integers(0, len(peaks), size=(10000, len(peaks)))
        means.append(peaks[indices].mean(axis=1))
    means = np.concatenate(means)
    return tuple(np.percentile(means, [2.5, 97.5]))


def make_dataset(seed):
    rng = np.random.default_rng(seed)
    rows = []
    outlier_index = int(rng.integers(20, 80))
    for i in range(100):
        row = rng.uniform(3.0, 9.0, size=100)
        target = float(rng.uniform(50.0, 67.0))
        if i == outlier_index:
            target = float(rng.uniform(780.0, 1150.0))

        if i % 17 == 0:
            row[0] = target
            row[1] = target - float(rng.uniform(16.0, 24.0))
        else:
            j = int(rng.integers(2, 97))
            row[j - 1] = target - float(rng.uniform(25.0, 34.0))
            row[j] = target
            row[j + 1] = target - float(rng.uniform(20.0, 31.0))

        # The real sensor transmits values rounded to two decimal places.
        rows.append([float(f"{v:.2f}") for v in row])
    return rows


def fetch_endpoint():
    try:
        with urllib.request.urlopen("http://127.0.0.1:8080/api/data", timeout=5) as response:
            body = response.read().decode("utf-8")
    except Exception as exc:
        fail(f"Failed to fetch Nginx proxy endpoint /api/data: {exc}")
    try:
        return json.loads(body)
    except json.JSONDecodeError:
        fail(f"Nginx response is not valid JSON: {body!r}")


def run_case(case_number, seed, redis_client):
    rows = make_dataset(seed)
    temporary = SENSOR_DATA + ".new"
    with open(temporary, "w", encoding="utf-8") as f:
        json.dump(rows, f)
    os.replace(temporary, SENSOR_DATA)

    peaks = smooth_peaks(rows)
    expected_hist = expected_histogram(peaks)
    expected_lower, expected_upper = bootstrap_reference(peaks)

    redis_client.delete("latest_stats")
    result = subprocess.run(
        [PIPELINE],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    if result.returncode != 0:
        fail(
            f"pipeline.sh failed in dynamic case {case_number} with exit code "
            f"{result.returncode}. stderr: {result.stderr[-1000:]}"
        )
    if redis_client.get("latest_stats") is None:
        fail("pipeline.sh did not populate Redis key latest_stats")

    data = fetch_endpoint()
    for key in ("ci_lower", "ci_upper", "hist_counts"):
        if key not in data:
            fail(f"Missing {key!r} in JSON response")

    if not isinstance(data["ci_lower"], (int, float)) or isinstance(data["ci_lower"], bool):
        fail("ci_lower must be numeric")
    if not isinstance(data["ci_upper"], (int, float)) or isinstance(data["ci_upper"], bool):
        fail("ci_upper must be numeric")
    if not math.isfinite(float(data["ci_lower"])) or not math.isfinite(float(data["ci_upper"])):
        fail("Confidence interval values must be finite")
    if data["hist_counts"] != expected_hist:
        fail(f"Histogram mismatch in case {case_number}: expected {expected_hist}, got {data['hist_counts']}")

    lower_error = abs(float(data["ci_lower"]) - float(expected_lower))
    if lower_error > 1.5:
        fail(
            f"Bootstrap ci_lower mismatch in case {case_number}: expected about "
            f"{expected_lower:.3f}, got {data['ci_lower']}"
        )

    # Around the upper tail, one additional resampled extreme observation moves
    # the finite-B percentile by approximately this amount.
    upper_tolerance = (float(np.max(peaks)) - float(np.mean(peaks[peaks < np.max(peaks)]))) / 100.0 + 2.0
    upper_error = abs(float(data["ci_upper"]) - float(expected_upper))
    if upper_error > upper_tolerance:
        fail(
            f"Bootstrap ci_upper mismatch in case {case_number}: expected about "
            f"{expected_upper:.3f}, got {data['ci_upper']}"
        )
    if float(data["ci_lower"]) > float(data["ci_upper"]):
        fail("ci_lower must not exceed ci_upper")


def main():
    check_pipeline_artifact()

    # Seed the file before supervisor starts the replacement sensor.
    with open(SENSOR_DATA, "w", encoding="utf-8") as f:
        json.dump(make_dataset(secrets.randbits(63)), f)
    install_controlled_sensor()

    redis_client = redis.Redis(host="127.0.0.1", port=6379, db=0)
    redis_client.ping()

    # Fresh, unpredictable datasets prevent hard-coded Redis payloads from
    # passing and force the submitted artifact to consume the sensor stream.
    run_case(1, secrets.randbits(63), redis_client)
    run_case(2, secrets.randbits(63), redis_client)


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/verify_pipeline.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
