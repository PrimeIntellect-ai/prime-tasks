#!/bin/bash
mkdir -p /logs/verifier

run_verification() {
    GO_DIR=/home/user/traffic_model
    VERIFIED_BIN=/tmp/traffic_model_verified

    [ -d "$GO_DIR" ] || return 1
    find "$GO_DIR" -type f -name '*.go' -print -quit | grep -q . || return 1

    rm -f "$VERIFIED_BIN"
    (cd "$GO_DIR" && timeout 90s go build -o "$VERIFIED_BIN" .) || \
        (cd "$GO_DIR" && timeout 90s env GO111MODULE=off go build -o "$VERIFIED_BIN" .) || return 1
    [ -x "$VERIFIED_BIN" ] || return 1
    [ "$(head -c 4 "$VERIFIED_BIN" | od -An -tx1 | tr -d ' \n')" = "7f454c46" ] || return 1

    # Stop whatever currently owns port 9090 so the freshly compiled submission,
    # rather than a pre-existing dummy process, must recreate the artifacts and server.
    python3 - <<'PY'
import os
import signal
import time

inodes = set()
for table in ('/proc/net/tcp', '/proc/net/tcp6'):
    try:
        with open(table) as f:
            next(f)
            for line in f:
                fields = line.split()
                if fields[1].rsplit(':', 1)[-1].upper() == '2382' and fields[3] == '0A':
                    inodes.add(fields[9])
    except OSError:
        pass

for proc in os.listdir('/proc'):
    if not proc.isdigit():
        continue
    fd_dir = f'/proc/{proc}/fd'
    try:
        for fd in os.listdir(fd_dir):
            try:
                target = os.readlink(f'{fd_dir}/{fd}')
            except OSError:
                continue
            if target.startswith('socket:[') and target[8:-1] in inodes:
                try:
                    os.kill(int(proc), signal.SIGTERM)
                except (ProcessLookupError, PermissionError):
                    pass
                break
    except OSError:
        pass

time.sleep(1)
PY

    rm -f /home/user/correlation.txt /home/user/mse.txt /home/user/benchmark.txt
    (cd "$GO_DIR" && exec "$VERIFIED_BIN") >/tmp/traffic_model_verified.log 2>&1 &
    SERVER_PID=$!

    ready=0
    for _ in $(seq 1 60); do
        if ! kill -0 "$SERVER_PID" 2>/dev/null; then
            cat /tmp/traffic_model_verified.log >&2 || true
            return 1
        fi
        if [ -f /home/user/correlation.txt ] && [ -f /home/user/mse.txt ] && [ -f /home/user/benchmark.txt ] && \
           curl -fsS --max-time 1 -H 'Authorization: Bearer my-secret-token' \
             'http://127.0.0.1:9090/predict?frame_id=5' >/dev/null 2>&1; then
            ready=1
            break
        fi
        sleep 1
    done
    [ "$ready" -eq 1 ] || return 1

    cat > /tmp/test_final_state.py <<'PYTEST'
import itertools
import json
import math
import os
import statistics
import subprocess
import time

import pytest
import requests

VIDEO = "/app/traffic.mp4"
FILES = [
    "/home/user/correlation.txt",
    "/home/user/mse.txt",
    "/home/user/benchmark.txt",
]
BASE_URL = "http://127.0.0.1:9090/predict"
AUTH = {"Authorization": "Bearer my-secret-token"}


def read_float(path):
    assert os.path.exists(path), f"Required file missing: {path}"
    assert os.path.isfile(path), f"Path is not a file: {path}"
    with open(path) as f:
        content = f.read().strip()
    try:
        value = float(content)
    except ValueError:
        pytest.fail(f"File {path} does not contain a valid float. Content: {content!r}")
    assert math.isfinite(value), f"File {path} must contain a finite float"
    return value


def video_variances():
    probe = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream=width,height", "-of", "csv=p=0:s=x", VIDEO],
        check=True, stdout=subprocess.PIPE, text=True,
    ).stdout.strip().splitlines()[0]
    width, height = map(int, probe.split("x"))
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", VIDEO, "-vf", "fps=1,format=gray",
         "-f", "rawvideo", "-pix_fmt", "gray", "pipe:1"],
        check=True, stdout=subprocess.PIPE,
    ).stdout
    frame_size = width * height
    assert frame_size > 0 and len(raw) >= frame_size * 5
    assert len(raw) % frame_size == 0
    result = []
    for offset in range(0, len(raw), frame_size):
        frame = raw[offset:offset + frame_size]
        mean = sum(frame) / frame_size
        result.append(sum((p - mean) ** 2 for p in frame) / frame_size)
    return result


Y = video_variances()
X = list(range(len(Y)))


def fit(xs, ys):
    mx = sum(xs) / len(xs)
    my = sum(ys) / len(ys)
    denom = sum((x - mx) ** 2 for x in xs)
    assert denom > 0
    slope = sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / denom
    return my - slope * mx, slope


INTERCEPT, SLOPE = fit(X, Y)
MEAN_X = sum(X) / len(X)
MEAN_Y = sum(Y) / len(Y)
EXPECTED_CORR = sum((x-MEAN_X)*(y-MEAN_Y) for x, y in zip(X, Y)) / math.sqrt(
    sum((x-MEAN_X)**2 for x in X) * sum((y-MEAN_Y)**2 for y in Y)
)


def pair_partitions(items):
    if not items:
        yield []
        return
    first = items[0]
    for i in range(1, len(items)):
        pair = (first, items[i])
        rest = items[1:i] + items[i+1:]
        for tail in pair_partitions(rest):
            yield [pair] + tail


def cv_mse_for_partition(partition):
    errors = []
    all_ids = set(range(len(Y)))
    for test_pair in partition:
        train = sorted(all_ids.difference(test_pair))
        a, b = fit([X[i] for i in train], [Y[i] for i in train])
        errors.append(sum((Y[i] - (a + b*X[i]))**2 for i in test_pair) / len(test_pair))
    return sum(errors) / len(errors)


# With ten one-second frames, every ordinary shuffled, sequential, or round-robin
# five-fold split is one of these partitions into five two-frame test folds.
VALID_CV_MSES = [cv_mse_for_partition(p) for p in pair_partitions(list(range(len(Y))))]


def predict(frame_id):
    response = requests.get(BASE_URL, params={"frame_id": frame_id}, headers=AUTH, timeout=5)
    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")
    assert set(data) == {"frame_id", "predicted_variance"}, f"Unexpected JSON structure: {data}"
    assert data["frame_id"] == frame_id
    assert isinstance(data["predicted_variance"], (float, int))
    value = float(data["predicted_variance"])
    assert math.isfinite(value)
    return value


def test_output_files_exist_and_are_floats():
    for path in FILES:
        read_float(path)


def test_go_code_directory_exists():
    go_dir = "/home/user/traffic_model/"
    assert os.path.exists(go_dir), f"Go code directory missing: {go_dir}"
    assert os.path.isdir(go_dir), f"Path is not a directory: {go_dir}"
    assert any(name.endswith(".go") for _, _, files in os.walk(go_dir) for name in files), "No Go source code found"
    assert os.path.isfile("/tmp/traffic_model_verified")
    assert os.access("/tmp/traffic_model_verified", os.X_OK)


def test_correlation_recomputed_from_video():
    actual = read_float("/home/user/correlation.txt")
    assert -1 <= actual <= 1
    assert actual == pytest.approx(EXPECTED_CORR, abs=0.01)


def test_five_fold_mse_recomputed_from_video():
    actual = read_float("/home/user/mse.txt")
    assert actual >= 0
    assert any(math.isclose(actual, expected, rel_tol=0.05, abs_tol=0.05)
               for expected in VALID_CV_MSES), \
        f"MSE {actual} is not the five-fold regression MSE for the video data"


def test_http_server_predict_endpoint():
    value = predict(5)
    # Frame numbering may begin at zero or one; both conventions train the same
    # slope, with an intercept shifted by one frame.
    candidates = [INTERCEPT + SLOPE*5, (INTERCEPT-SLOPE) + SLOPE*5]
    assert any(math.isclose(value, expected, rel_tol=0.001, abs_tol=0.25)
               for expected in candidates)


def test_predictions_are_the_trained_regression_not_a_constant():
    ids = [-2, 0, 3, 9, 12]
    values = [predict(i) for i in ids]
    candidate_lines = [
        [INTERCEPT + SLOPE*i for i in ids],
        [(INTERCEPT-SLOPE) + SLOPE*i for i in ids],
    ]
    assert any(all(math.isclose(got, expected, rel_tol=0.001, abs_tol=0.25)
                   for got, expected in zip(values, line)) for line in candidate_lines)
    response_slope = (values[-1] - values[0]) / (ids[-1] - ids[0])
    assert math.isclose(response_slope, SLOPE, rel_tol=0.10, abs_tol=0.01)


def test_http_server_auth_required():
    response = requests.get(BASE_URL, params={"frame_id": 5}, timeout=5)
    assert response.status_code != 200, "Server allowed access without Authorization header"
    wrong = requests.get(BASE_URL, params={"frame_id": 5},
                         headers={"Authorization": "Bearer wrong-token"}, timeout=5)
    assert wrong.status_code != 200, "Server allowed an incorrect token"


def test_benchmark_is_plausible_against_1000_live_inferences():
    reported_us = read_float("/home/user/benchmark.txt")
    assert reported_us >= 0
    session = requests.Session()
    start = time.perf_counter_ns()
    for i in range(1000):
        response = session.get(BASE_URL, params={"frame_id": i % len(Y)}, headers=AUTH, timeout=5)
        assert response.status_code == 200
        data = response.json()
        assert data["frame_id"] == i % len(Y)
        assert math.isfinite(float(data["predicted_variance"]))
    live_average_us = (time.perf_counter_ns() - start) / 1000.0 / 1000.0
    # A pure arithmetic model inference cannot reasonably exceed the complete
    # authenticated HTTP round trip measured above.
    assert reported_us <= live_average_us * 2 + 1
PYTEST

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short
}

if run_verification 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
