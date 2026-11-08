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
import csv
import json
import math
import os
import random
import re
import secrets
import signal
import socket
import subprocess
import time
from pathlib import Path

import pytest
import requests

BASE_URL = "http://127.0.0.1:8000/api/v1/correlation"
DATASET = Path("/app/dataset.csv")
TOKEN_IMAGE = Path("/app/auth_token.png")


def correlation_from_dataset():
    xs, ys = [], []
    with DATASET.open(newline="") as f:
        for row in csv.DictReader(f):
            if row["split"] == "train":
                xs.append(float(row["featureA"]))
                ys.append(float(row["featureB"]))
    assert len(xs) >= 2
    mx = sum(xs) / len(xs)
    my = sum(ys) / len(ys)
    numerator = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
    denominator = math.sqrt(
        sum((x - mx) ** 2 for x in xs) * sum((y - my) ** 2 for y in ys)
    )
    return round(numerator / denominator, 4)


def token_from_image():
    result = subprocess.run(
        ["tesseract", str(TOKEN_IMAGE), "stdout", "--psm", "7"],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    token = result.stdout.rstrip()
    assert token, "OCR produced an empty token"
    return token


def assert_no_auth_and_invalid(token):
    try:
        response = requests.get(BASE_URL, timeout=5)
    except requests.exceptions.ConnectionError:
        pytest.fail("Could not connect to the server. Is it running on 127.0.0.1:8000?")
    assert response.status_code == 401, f"Expected 401 Unauthorized, got {response.status_code}"

    response = requests.get(
        BASE_URL,
        headers={"Authorization": "Bearer INVALID_TOKEN"},
        timeout=5,
    )
    assert response.status_code == 401, f"Expected 401 Unauthorized, got {response.status_code}"

    response = requests.get(
        BASE_URL,
        headers={"Authorization": token},
        timeout=5,
    )
    assert response.status_code == 401, "Authorization must use the Bearer <TOKEN> format"


def assert_valid_response(token, expected):
    response = requests.get(
        BASE_URL,
        headers={"Authorization": f"Bearer {token}"},
        timeout=5,
    )
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail("Response is not valid JSON")

    assert isinstance(data, dict), "Response JSON must be an object"
    assert set(data) == {"correlation"}, "Response must contain exactly the correlation field"
    actual = data["correlation"]
    assert isinstance(actual, (int, float)) and not isinstance(actual, bool), \
        "correlation must be a JSON number, not a string"
    assert abs(actual - expected) < 1e-4, f"Expected correlation {expected}, got {actual}"
    assert re.fullmatch(
        r'\s*\{\s*"correlation"\s*:\s*-?\d+\.\d{4}\s*\}\s*',
        response.text,
    ), "Response must have exactly one numeric correlation rounded to four decimal places"


def listener_pids():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) < 10:
                continue
            try:
                port = int(fields[1].rsplit(":", 1)[1], 16)
            except ValueError:
                continue
            if port == 8000 and fields[3] == "0A":
                inodes.add(fields[9])

    found = set()
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / "fd").iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    found.add(int(proc.name))
                    break
        except OSError:
            pass
    return found


def process_launch_info(pid):
    cmdline = Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0")
    command = [part.decode(errors="surrogateescape") for part in cmdline if part]
    assert command, "Could not determine how to restart the submitted server"
    cwd = os.readlink(f"/proc/{pid}/cwd")
    env = os.environ.copy()
    try:
        entries = Path(f"/proc/{pid}/environ").read_bytes().split(b"\0")
        for entry in entries:
            if b"=" in entry:
                key, value = entry.split(b"=", 1)
                env[key.decode(errors="surrogateescape")] = value.decode(errors="surrogateescape")
    except OSError:
        pass
    return command, cwd, env


def wait_ready(timeout):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", 8000), timeout=0.25):
                return True
        except OSError:
            time.sleep(0.1)
    return False


def restart_server_after_inputs_change():
    pids = listener_pids()
    assert pids, "No process is listening on port 8000"
    command, cwd, env = process_launch_info(min(pids))

    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and any(Path(f"/proc/{pid}").exists() for pid in pids):
        time.sleep(0.05)
    for pid in pids:
        if Path(f"/proc/{pid}").exists():
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass

    # A supervisor or development reloader may already have started a fresh worker.
    if wait_ready(1.5):
        return

    with open("/tmp/restarted-server.log", "ab", buffering=0) as log:
        subprocess.Popen(
            command,
            cwd=cwd,
            env=env,
            stdin=subprocess.DEVNULL,
            stdout=log,
            stderr=log,
            start_new_session=True,
        )
    assert wait_ready(8), "The submitted server could not be restarted after its inputs changed"


def install_random_inputs(initial_correlation):
    rng = random.SystemRandom()
    alphabet = "ACEFHKMNPRTUVWXY3479"
    token = "ETLTOKEN" + "".join(secrets.choice(alphabet) for _ in range(12))

    while True:
        xs = [i * 2.0 + rng.uniform(-0.7, 0.7) for i in range(1, 10)]
        ys = [2.1 * x + rng.uniform(-7.0, 7.0) for x in xs]
        mx, my = sum(xs) / len(xs), sum(ys) / len(ys)
        corr = sum((x-mx)*(y-my) for x, y in zip(xs, ys)) / math.sqrt(
            sum((x-mx)**2 for x in xs) * sum((y-my)**2 for y in ys)
        )
        rounded = round(corr, 4)
        if rounded != initial_correlation and f"{rounded:.4f}"[-1] != "0":
            break

    with DATASET.open("w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["id", "featureA", "featureB", "split"])
        for i, (x, y) in enumerate(zip(xs, ys), 1):
            writer.writerow([i, f"{x:.10f}", f"{y:.10f}", "train"])
        # Test rows deliberately have a very different relationship and must be ignored.
        for j in range(4):
            writer.writerow([100+j, 1000+j*100, -5000-j*900, "test"])

    subprocess.run(
        [
            "convert", "-size", "700x110", "xc:white", "-font", "DejaVu-Sans",
            "-pointsize", "28", "-fill", "black", "-draw", f"text 20,68 '{token}'",
            str(TOKEN_IMAGE),
        ],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return token, correlation_from_dataset()


def test_pipeline_and_api():
    initial_token = token_from_image()
    initial_correlation = correlation_from_dataset()
    assert_no_auth_and_invalid(initial_token)
    assert_valid_response(initial_token, initial_correlation)

    new_token, new_correlation = install_random_inputs(initial_correlation)
    restart_server_after_inputs_change()

    # The former token must no longer authenticate after the image changes.
    old_response = requests.get(
        BASE_URL,
        headers={"Authorization": f"Bearer {initial_token}"},
        timeout=5,
    )
    assert old_response.status_code == 401
    assert_no_auth_and_invalid(new_token)
    assert_valid_response(new_token, new_correlation)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
