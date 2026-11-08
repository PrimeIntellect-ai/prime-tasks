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
import csv
import os
import re
import secrets
import signal
import subprocess
import tempfile
import time

import pytest
import requests

VIDEO_PATH = "/app/traffic_feed.mp4"
CSV_PATH = "/app/radar_sensors.csv"
LOG_PATH = "/home/user/etl_experiment.log"
SERVER_URL = "http://127.0.0.1:8080/posterior"
AUTH_HEADER = {"X-Auth-Token": "etl-agent-secret"}


def find_listener():
    inodes = set()
    try:
        with open("/proc/net/tcp", "r") as f:
            for line in f.readlines()[1:]:
                fields = line.split()
                local, state, inode = fields[1], fields[3], fields[9]
                address, port = local.split(":")
                if address == "0100007F" and int(port, 16) == 8080 and state == "0A":
                    inodes.add(inode)
    except OSError:
        return None

    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    return int(name)
        except OSError:
            continue
    return None


def stop_listener():
    pid = find_listener()
    if pid is None:
        return
    assert pid > 1
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    for _ in range(30):
        if find_listener() is None:
            return
        time.sleep(0.1)
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    for _ in range(30):
        if find_listener() is None:
            return
        time.sleep(0.1)
    pytest.fail("Could not stop the existing server on 127.0.0.1:8080")


def c_sources():
    result = []
    for root in ("/app", "/home/user"):
        for directory, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if not d.startswith(".")]
            for filename in files:
                if filename.endswith(".c"):
                    result.append(os.path.join(directory, filename))
    return result


def write_challenge_csv():
    rows = []
    with open(CSV_PATH, newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            rows.append(row)

    assert {int(r["timestamp_sec"]) for r in rows} == set(range(10))
    chosen = set()
    for row in rows:
        while True:
            prior = (secrets.randbelow(89) + 6) / 100.0
            if prior not in chosen:
                chosen.add(prior)
                break
        row["prior_prob_speeding"] = f"{prior:.2f}"

    with open(CSV_PATH, "w", newline="") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=["timestamp_sec", "noisy_speed_mph", "prior_prob_speeding"],
        )
        writer.writeheader()
        writer.writerows(rows)


def wait_for_listener(timeout=25):
    deadline = time.time() + timeout
    while time.time() < deadline:
        pid = find_listener()
        if pid is not None:
            return pid
        time.sleep(0.1)
    return None


@pytest.fixture(scope="session", autouse=True)
def compiled_server():
    """Require the submitted listener to be native, then rebuild and execute its C source."""
    original_pid = find_listener()
    assert original_pid is not None, "No server listening specifically on 127.0.0.1:8080"
    original_exe = f"/proc/{original_pid}/exe"
    try:
        with open(original_exe, "rb") as f:
            assert f.read(4) == b"\x7fELF", "The submitted HTTP server is not a native executable"
        original_path = os.readlink(original_exe).replace(" (deleted)", "")
    except OSError as exc:
        pytest.fail(f"Cannot inspect submitted server executable: {exc}")

    sources = c_sources()
    assert sources, "No C source file was supplied under /app or /home/user"

    stem = os.path.splitext(os.path.basename(original_path))[0]
    sources.sort(key=lambda p: (os.path.splitext(os.path.basename(p))[0] != stem, p))

    # Use unpredictable priors and a fresh log so fixed responses and prewritten
    # experiment records cannot satisfy the checks.
    write_challenge_csv()
    stop_listener()

    build_attempts = [[src] for src in sources]
    for directory in sorted({os.path.dirname(src) for src in sources}):
        group = sorted(src for src in sources if os.path.dirname(src) == directory)
        if len(group) > 1:
            build_attempts.append(group)

    diagnostics = []
    selected = None
    for index, source_group in enumerate(build_attempts):
        output = f"/tmp/verified_etl_pipeline_{index}"
        command = ["gcc", "-O2", "-o", output] + source_group + ["-lm", "-pthread"]
        built = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        if built.returncode != 0:
            diagnostics.append(f"{source_group}: compile failed")
            continue

        with open(LOG_PATH, "w"):
            pass
        process = subprocess.Popen(
            [output],
            cwd=os.path.dirname(source_group[0]),
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        listener_pid = wait_for_listener()
        if listener_pid is None:
            diagnostics.append(f"{source_group}: compiled program did not listen")
            if process.poll() is None:
                process.kill()
            continue

        try:
            listener_exe = os.readlink(f"/proc/{listener_pid}/exe").replace(" (deleted)", "")
            same_binary = os.path.samefile(listener_exe, output)
        except OSError:
            same_binary = False

        if not same_binary:
            diagnostics.append(f"{source_group}: listener was not the compiled C executable")
            stop_listener()
            if process.poll() is None:
                process.kill()
            continue

        try:
            response = requests.get(f"{SERVER_URL}?sec=0", headers=AUTH_HEADER, timeout=2)
            ready = response.status_code == 200
            float(response.text.strip())
        except (requests.RequestException, ValueError):
            ready = False

        if not ready:
            diagnostics.append(f"{source_group}: compiled listener did not serve the endpoint")
            stop_listener()
            if process.poll() is None:
                process.kill()
            continue

        selected = (process, listener_pid, source_group)
        break

    assert selected is not None, "No supplied C source rebuilt into the HTTP listener: " + "; ".join(diagnostics)
    return selected


@pytest.fixture(scope="session")
def ground_truth(compiled_server):
    """Compute the ground truth posteriors independently from the current inputs."""
    assert os.path.isfile(VIDEO_PATH), f"Video missing: {VIDEO_PATH}"
    assert os.path.isfile(CSV_PATH), f"CSV missing: {CSV_PATH}"

    priors = {}
    with open(CSV_PATH, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            sec = int(row["timestamp_sec"])
            prior = float(row["prior_prob_speeding"])
            priors[sec] = prior

    temp_dir = tempfile.mkdtemp()
    try:
        cmd = [
            "ffmpeg", "-i", VIDEO_PATH,
            "-q:v", "2",
            os.path.join(temp_dir, "frame_%04d.jpg"),
        ]
        subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
        frames = sorted(
            f for f in os.listdir(temp_dir)
            if f.startswith("frame_") and f.endswith(".jpg")
        )

        posteriors = {}
        for sec, prior in priors.items():
            sec_frames = frames[sec * 24:(sec + 1) * 24]
            if not sec_frames:
                continue
            max_size = max(os.path.getsize(os.path.join(temp_dir, f)) for f in sec_frames)
            if max_size > 50000:
                ls, lns = 0.8, 0.4
            else:
                ls, lns = 0.3, 0.7
            evidence = ls * prior + lns * (1.0 - prior)
            posterior = ls * prior / evidence
            posteriors[sec] = {"prior": prior, "posterior": posterior, "max_size": max_size}
        return posteriors
    finally:
        for filename in os.listdir(temp_dir):
            os.remove(os.path.join(temp_dir, filename))
        os.rmdir(temp_dir)


def test_server_authorized_requests(ground_truth):
    """Test every joined second using independently derived answers."""
    assert set(ground_truth) == set(range(10))
    for sec in sorted(ground_truth):
        expected_posterior = ground_truth[sec]["posterior"]
        try:
            resp = requests.get(f"{SERVER_URL}?sec={sec}", headers=AUTH_HEADER, timeout=2)
        except requests.exceptions.RequestException as e:
            pytest.fail(f"Failed to connect to server: {e}")

        assert resp.status_code == 200, f"Expected 200 OK for sec={sec}, got {resp.status_code}"
        try:
            actual_posterior = float(resp.text.strip())
        except ValueError:
            pytest.fail(f"Expected float in response body, got: {resp.text}")
        assert re.fullmatch(r"[0-9]+\.[0-9]{4}\s*", resp.text), \
            f"Response for sec={sec} was not formatted to 4 decimal places: {resp.text!r}"
        assert abs(actual_posterior - expected_posterior) < 0.001, \
            f"Posterior mismatch for sec={sec}. Expected ~{expected_posterior:.4f}, got {actual_posterior:.4f}"


def test_server_unauthorized_request(compiled_server):
    try:
        resp = requests.get(f"{SERVER_URL}?sec=0", timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to server: {e}")
    assert resp.status_code == 401, f"Expected 401 Unauthorized, got {resp.status_code}"


def test_experiment_log(ground_truth):
    assert os.path.isfile(LOG_PATH), f"Log file missing: {LOG_PATH}"
    with open(LOG_PATH, "r") as f:
        log_content = f.read()

    parsed = {}
    for match in re.finditer(
        r"^\[RUN\]\s+sec=(\d+)\s+prior=([0-9.]+)\s+posterior=([0-9.]+)\s*$",
        log_content,
        re.MULTILINE,
    ):
        parsed[int(match.group(1))] = (float(match.group(2)), float(match.group(3)))

    for sec, data in ground_truth.items():
        prior = data["prior"]
        posterior = data["posterior"]

        # Retain the original flexible posterior assertion.
        flexible_pattern = rf"\[RUN\]\s+sec={sec}\s+prior=[0-9.]+\s+posterior={posterior:.4f}"
        assert re.search(flexible_pattern, log_content) is not None, \
            f"Could not find matching log entry for sec={sec} with posterior ~{posterior:.4f} in {LOG_PATH}"

        assert sec in parsed, f"Missing well-formed log entry for sec={sec}"
        actual_prior, actual_posterior = parsed[sec]
        assert abs(actual_prior - prior) < 1e-6, f"Logged prior is wrong for sec={sec}"
        assert abs(actual_posterior - posterior) < 0.001, f"Logged posterior is wrong for sec={sec}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
