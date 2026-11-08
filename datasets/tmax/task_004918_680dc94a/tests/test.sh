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
import cv2
import math
import os
import signal
import subprocess
import time

import numpy as np
import requests
from scipy.special import gammaln
from scipy.stats import wasserstein_distance

URL = "http://127.0.0.1:8888/analysis"
HEADERS = {"Authorization": "Bearer perf-agent-secret"}
VIDEO = "/app/integrator_profile.mp4"


def authorized_request(timeout_total=30):
    deadline = time.time() + timeout_total
    last_error = None
    while time.time() < deadline:
        try:
            response = requests.get(URL, headers=HEADERS, timeout=5)
            if response.status_code == 200:
                return response
            last_error = AssertionError(
                f"Expected status code 200, got {response.status_code}. Response body: {response.text}"
            )
        except requests.RequestException as exc:
            last_error = exc
        time.sleep(0.5)
    raise AssertionError(f"Could not obtain a successful response from {URL}: {last_error}")


def assert_payload(response):
    try:
        data = response.json()
    except ValueError:
        raise AssertionError(f"Response is not valid JSON: {response.text}")

    assert "wasserstein" in data, "Missing 'wasserstein' key in JSON response"
    assert "posterior_mean" in data, "Missing 'posterior_mean' key in JSON response"
    assert "posterior_std" in data, "Missing 'posterior_std' key in JSON response"
    assert set(data) == {"wasserstein", "posterior_mean", "posterior_std"}, \
        f"JSON response must contain exactly the required keys, got {sorted(data)}"

    for key in ("wasserstein", "posterior_mean", "posterior_std"):
        assert isinstance(data[key], (int, float)) and not isinstance(data[key], bool), \
            f"{key} must be a number, got {type(data[key])}"
        assert math.isfinite(float(data[key])), f"{key} must be finite"
    return data


def find_listener_pid(port=8888):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[3] == "0A" and fields[1].split(":")[-1].upper() == wanted:
                        inodes.add(fields[9])
        except OSError:
            pass
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
            continue
    return None


def restart_server():
    pid = find_listener_pid()
    assert pid is not None, "Could not identify the process listening on port 8888"
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            argv = [x.decode() for x in f.read().split(b"\0") if x]
        cwd = os.readlink(f"/proc/{pid}/cwd")
        with open(f"/proc/{pid}/environ", "rb") as f:
            entries = [x for x in f.read().split(b"\0") if x]
        env = {}
        for entry in entries:
            key, sep, value = entry.partition(b"=")
            if sep:
                env[key.decode(errors="surrogateescape")] = value.decode(errors="surrogateescape")
    except OSError as exc:
        raise AssertionError(f"Could not capture API server launch information: {exc}")

    assert argv, "API server has an empty command line"
    os.kill(pid, signal.SIGTERM)
    deadline = time.time() + 8
    while time.time() < deadline and find_listener_pid() is not None:
        time.sleep(0.2)
    if find_listener_pid() is not None:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        time.sleep(0.5)
    assert find_listener_pid() is None, "The original API server did not release port 8888"

    subprocess.Popen(
        argv,
        cwd=cwd,
        env=env or os.environ.copy(),
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


def write_randomized_video(path):
    seed = int.from_bytes(os.urandom(8), "little")
    rng = np.random.default_rng(seed)
    phase1 = rng.integers(70, 151, size=50)
    phase2 = np.clip(np.rint(rng.normal(370, 34, size=50)), 285, 450).astype(int)
    ys = np.concatenate([phase1, phase2])

    writer = cv2.VideoWriter(path, cv2.VideoWriter_fourcc(*"mp4v"), 10, (640, 480))
    assert writer.isOpened(), "Could not create randomized verification video"
    for i, y in enumerate(ys):
        image = np.zeros((480, 640, 3), dtype=np.uint8)
        x = i * 6
        image[int(y):int(y) + 2, x:x + 2] = (0, 0, 255)
        writer.write(image)
    writer.release()


def extract_y_values(path):
    cap = cv2.VideoCapture(path)
    values = []
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        b, g, r = cv2.split(frame.astype(np.int16))
        score = r - np.maximum(g, b)
        max_score = int(score.max())
        assert max_score > 80, "Randomized video frame does not contain a detectable red dot"
        rows, _ = np.where(score >= max_score - 12)
        values.append(float(np.median(rows)))
    cap.release()
    assert len(values) == 100, f"Expected randomized video to contain 100 frames, got {len(values)}"
    return np.asarray(values)


def posterior_expectations(values):
    n = len(values)
    mean = float(np.mean(values))
    sse = float(np.sum((values - mean) ** 2))
    # With the stated uniform priors and these deliberately interior values, the
    # finite prior boundaries have negligible mass. This is the normalized
    # posterior expectation after analytically integrating the normal mean.
    expected_sigma = math.sqrt(sse / 2.0) * math.exp(
        gammaln((n - 3) / 2.0) - gammaln((n - 2) / 2.0)
    )
    return mean, expected_sigma


def test_complete_analysis_and_api():
    # Preserve the original checks against the supplied artifact.
    response = authorized_request()
    original = assert_payload(response)
    assert 48.5 <= original["wasserstein"] <= 49.5, \
        f"wasserstein value {original['wasserstein']} is out of expected range [48.5, 49.5]"
    assert 288.0 <= original["posterior_mean"] <= 290.0, \
        f"posterior_mean value {original['posterior_mean']} is out of expected range [288.0, 290.0]"
    assert 26.0 <= original["posterior_std"] <= 31.0, \
        f"posterior_std value {original['posterior_std']} is out of expected range [26.0, 31.0]"

    # Preserve the original authorization assertion.
    unauthorized = requests.get(URL, timeout=5)
    if unauthorized.status_code == 200:
        try:
            unauthorized_data = unauthorized.json()
            assert "wasserstein" not in unauthorized_data, \
                "API returned the analysis data without the required Authorization header."
        except ValueError:
            pass

    wrong = requests.get(URL, headers={"Authorization": "Bearer wrong-secret"}, timeout=5)
    if wrong.status_code == 200:
        try:
            assert "wasserstein" not in wrong.json(), \
                "API returned analysis data for an incorrect Authorization header."
        except ValueError:
            pass

    backup = VIDEO + ".verifier-backup"
    with open(VIDEO, "rb") as src, open(backup, "wb") as dst:
        dst.write(src.read())
    try:
        write_randomized_video(VIDEO)
        observed = extract_y_values(VIDEO)
        expected_w = float(wasserstein_distance(observed[:50], observed[50:]))
        expected_mean, expected_std = posterior_expectations(observed[50:])

        restart_server()
        challenged = assert_payload(authorized_request(timeout_total=45))

        assert abs(float(challenged["wasserstein"]) - expected_w) <= 2.0, \
            f"wasserstein was not recomputed from the randomized video: expected about {expected_w}, got {challenged['wasserstein']}"
        assert abs(float(challenged["posterior_mean"]) - expected_mean) <= 4.0, \
            f"posterior_mean is inconsistent with the randomized Phase 2 posterior: expected about {expected_mean}, got {challenged['posterior_mean']}"
        assert abs(float(challenged["posterior_std"]) - expected_std) <= 5.0, \
            f"posterior_std is inconsistent with the randomized Phase 2 posterior: expected about {expected_std}, got {challenged['posterior_std']}"
    finally:
        if os.path.exists(backup):
            os.replace(backup, VIDEO)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
