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
import datetime
import os
import pathlib
import random
import re
import signal
import socket
import subprocess
import time

import pytest
import requests

URL = "http://127.0.0.1:8080/metrics"
CSV = pathlib.Path("/app/loc_events.csv")


def get_metrics(timeout=5):
    try:
        response = requests.get(URL, timeout=timeout)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to {URL}. Is the service running? Error: {e}")
    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"
    try:
        return response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response body: {response.text}")


def listener_pid():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = pathlib.Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[1].split(":")[-1].upper() == "1F90" and fields[3] == "0A":
                inodes.add(fields[9])
    for proc in pathlib.Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        fd_dir = proc / "fd"
        try:
            for fd in fd_dir.iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                m = re.fullmatch(r"socket:\[(\d+)\]", target)
                if m and m.group(1) in inodes:
                    return int(proc.name)
        except OSError:
            pass
    return None


def process_description(pid):
    argv = pathlib.Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0")
    argv = [x.decode(errors="surrogateescape") for x in argv if x]
    cwd = os.readlink(f"/proc/{pid}/cwd")
    env = os.environ.copy()
    try:
        entries = pathlib.Path(f"/proc/{pid}/environ").read_bytes().split(b"\0")
        captured = {}
        for entry in entries:
            if b"=" in entry:
                k, v = entry.split(b"=", 1)
                captured[k.decode(errors="ignore")] = v.decode(errors="surrogateescape")
        if captured:
            env = captured
    except OSError:
        pass
    return argv, cwd, env


def stop_listener():
    pid = listener_pid()
    if pid is None:
        return
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    for _ in range(20):
        if listener_pid() != pid:
            return
        time.sleep(0.1)
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    time.sleep(0.2)


def wait_for_expected(expected, seconds=5):
    deadline = time.time() + seconds
    last = None
    while time.time() < deadline:
        try:
            r = requests.get(URL, timeout=0.5)
            if r.status_code == 200:
                last = r.json()
                if last == expected:
                    return True
        except Exception:
            pass
        time.sleep(0.15)
    return False


def find_cpp_sources():
    result = []
    for root_name in ("/app", "/home/user", "/tmp"):
        root = pathlib.Path(root_name)
        if not root.exists():
            continue
        for p in root.rglob("*"):
            if p.is_file() and p.suffix.lower() in (".cpp", ".cc", ".cxx"):
                if p.name != "test_final_state.py" and "/tests/" not in str(p):
                    result.append(p)
    return sorted(set(result))


def source_has_core_transform(text):
    lower = text.lower()
    reads_csv = "loc_events.csv" in lower and ("ifstream" in lower or "fopen" in lower or "fstream" in lower)
    parses_rows = "getline" in lower or "strtok" in lower
    aggregates = "map<" in lower or "unordered_map<" in lower or "std::map" in lower or "std::unordered_map" in lower
    converts_date = any(token in lower for token in ("gmtime", "strftime", "time_t", "sys_days", "year_month_day"))
    return reads_csv and parses_rows and aggregates and converts_date


def compile_candidates(sources):
    variants = []
    by_dir = {}
    for src in sources:
        by_dir.setdefault(src.parent, []).append(src)
    for files in by_dir.values():
        variants.append(files)
        variants.extend([[p] for p in files])

    seen = set()
    built = []
    for index, files in enumerate(variants):
        key = tuple(sorted(map(str, files)))
        if key in seen:
            continue
        seen.add(key)
        text = "\n".join(p.read_text(errors="ignore") for p in files)
        if not source_has_core_transform(text):
            continue
        output = f"/tmp/verifier_cpp_candidate_{index}"
        command = ["g++", "-std=c++17", "-O2", "-pthread", *map(str, files), "-o", output]
        result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
        if result.returncode == 0:
            built.append((output, str(files[0].parent)))
    return built


def test_metrics_endpoint_and_cpp_transformation():
    # Preserve the original fixed-fixture assertion.
    expected_data = {
        "2023-10-01": 22,
        "2023-10-02": 20,
        "2023-10-03": 15,
    }
    data = get_metrics()
    assert data == expected_data, f"JSON response data does not match expected output.\nExpected: {expected_data}\nGot: {data}"

    sources = find_cpp_sources()
    assert sources, "No submitted C++ source file was found"
    candidates = compile_candidates(sources)
    assert candidates, "No compilable submitted C++ program implementing CSV parsing, UTC date conversion, and aggregation was found"

    old_pid = listener_pid()
    assert old_pid is not None, "No process is listening on port 8080"
    old_argv, old_cwd, old_env = process_description(old_pid)

    rng = random.SystemRandom()
    rows = [
        (1696118400, "CHECKOUT_PROCEED_BUTTON", "en-US", rng.randrange(31, 91)),
        (1696161600, "CHECKOUT_PROCEED_BUTTON", "fr-FR", rng.randrange(7, 29)),
        (1696204800, "CHECKOUT_PROCEED_BUTTON", "es-ES", rng.randrange(101, 171)),
        (1696377600, "CHECKOUT_PROCEED_BUTTON", "de-DE", rng.randrange(201, 281)),
        (1696118400, "OTHER_BUTTON", "en-US", rng.randrange(500, 900)),
        (1696291200, "UNRELATED_LABEL", "ja-JP", rng.randrange(500, 900)),
    ]
    expected_dynamic = {}
    for timestamp, identifier, locale, views in rows:
        if identifier == "CHECKOUT_PROCEED_BUTTON":
            day = datetime.datetime.fromtimestamp(timestamp, datetime.timezone.utc).strftime("%Y-%m-%d")
            expected_dynamic[day] = expected_dynamic.get(day, 0) + views

    fixture = "timestamp,ui_string,locale,views\n" + "".join(
        f"{timestamp},{identifier},{locale},{views}\n"
        for timestamp, identifier, locale, views in rows
    )
    CSV.write_text(fixture)

    success = False
    for executable, cwd in candidates:
        stop_listener()
        CSV.write_text(fixture)
        proc = subprocess.Popen([executable], cwd=cwd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(0.8)

        if proc.poll() is None and wait_for_expected(expected_dynamic, 4):
            success = True
            break

        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=1)
            except subprocess.TimeoutExpired:
                proc.kill()
        stop_listener()

        # A permitted design may use C++ only as a preprocessing step and a
        # separate HTTP tool. Restart the original serving command after the
        # freshly compiled C++ processor has consumed the changed CSV.
        try:
            subprocess.Popen(old_argv, cwd=old_cwd, env=old_env,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception:
            continue
        if wait_for_expected(expected_dynamic, 4):
            success = True
            break

    assert success, (
        "The submitted C++ program and service did not recompute /metrics from a changed CSV fixture; "
        f"expected {expected_dynamic}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
