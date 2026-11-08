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
import glob
import os
import secrets
import subprocess
import tempfile
import time

import pytest
import requests

FILTER = "/app/bash-csv-toolkit-1.2/filter_valid.sh"
SUM_FILE = "/home/user/sum.txt"


def read_valid_rows(file_path, minimum):
    valid = []
    with open(file_path, "r") as f:
        lines = f.readlines()
    for line in lines[1:]:
        parts = line.strip().split(",")
        if len(parts) >= 4:
            try:
                age = int(parts[2])
                score = int(parts[3])
            except ValueError:
                continue
            if age >= 18 and score >= minimum:
                valid.append(line.strip())
    return valid


def compute_expected_sum():
    return sum(
        int(row.split(",")[3])
        for file_path in glob.glob("/home/user/data/part_*.csv")
        for row in read_valid_rows(file_path, 50)
    )


def run_filter(file_path, minimum):
    env = os.environ.copy()
    env["MIN_SCORE"] = str(minimum)
    result = subprocess.run(
        ["bash", FILTER, file_path],
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )
    assert result.returncode == 0, result.stderr
    return [line for line in result.stdout.splitlines() if line]


def test_filter_valid_script_fixed_and_functional():
    assert os.path.isfile(FILTER), f"File {FILTER} does not exist."

    with open(FILTER, "r") as f:
        content = f.read()

    assert 'MIN_SCOR=' not in content, "The typo 'MIN_SCOR=' is still present in the script."
    assert 'MIN_SCORE=\"$MIN_SCORE\"' in content or 'MIN_SCORE=' in content, \
        "The script does not properly assign MIN_SCORE."

    syntax = subprocess.run(["bash", "-n", FILTER], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert syntax.returncode == 0, f"filter_valid.sh is not valid Bash: {syntax.stderr}"

    # Exercise the submitted script on verifier-generated data and thresholds.
    threshold = 37 + secrets.randbelow(47)
    rows = [
        (1, "underage-high", 17, threshold + 40),
        (2, "adult-low", 35, threshold - 1),
        (3, "age-boundary", 18, threshold),
        (4, "valid-high", 61, threshold + 23),
        (5, "underage-boundary", 17, threshold),
    ]
    with tempfile.TemporaryDirectory() as directory:
        path = os.path.join(directory, "generated.csv")
        with open(path, "w") as f:
            f.write("id,name,age,score\n")
            for row in rows:
                f.write(",".join(map(str, row)) + "\n")

        expected = [",".join(map(str, row)) for row in rows if row[2] >= 18 and row[3] >= threshold]
        assert run_filter(path, threshold) == expected

        # Also verify the script's documented default when MIN_SCORE is absent.
        env = os.environ.copy()
        env.pop("MIN_SCORE", None)
        result = subprocess.run(
            ["bash", FILTER, path], env=env, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5
        )
        assert result.returncode == 0, result.stderr
        default_expected = [",".join(map(str, row)) for row in rows if row[2] >= 18 and row[3] >= 0]
        assert [line for line in result.stdout.splitlines() if line] == default_expected


def test_all_five_files_with_filter_in_parallel_and_sum_file_correct():
    csv_files = sorted(glob.glob("/home/user/data/part_*.csv"))
    assert csv_files == [f"/home/user/data/part_{i}.csv" for i in range(1, 6)]

    env = os.environ.copy()
    env["MIN_SCORE"] = "50"
    # Start all five filter processes before collecting any result.
    processes = [
        (path, subprocess.Popen(
            ["bash", FILTER, path], env=env, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE
        ))
        for path in csv_files
    ]

    filtered_rows = []
    for path, process in processes:
        stdout, stderr = process.communicate(timeout=5)
        assert process.returncode == 0, f"Filtering {path} failed: {stderr}"
        actual = [line for line in stdout.splitlines() if line]
        expected = read_valid_rows(path, 50)
        assert actual == expected, f"Incorrect filtered output for {path}"
        filtered_rows.extend(actual)

    expected_sum = compute_expected_sum()
    filtered_sum = sum(int(row.split(",")[3]) for row in filtered_rows)
    assert filtered_sum == expected_sum

    assert os.path.isfile(SUM_FILE), f"File {SUM_FILE} does not exist."
    with open(SUM_FILE, "r") as f:
        content = f.read().strip()
    assert content == str(expected_sum), f"Expected sum {expected_sum} in {SUM_FILE}, but got {content}."


def nc_listener_pids():
    inodes = set()
    try:
        with open("/proc/net/tcp", "r") as f:
            for line in f.readlines()[1:]:
                fields = line.split()
                local_address, state = fields[1], fields[3]
                if local_address == "0100007F:1F90" and state == "0A":
                    inodes.add(fields[9])
    except OSError:
        return []

    matches = []
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            owns_socket = any(
                os.readlink(os.path.join(fd_dir, fd)) == f"socket:[{inode}]"
                for fd in os.listdir(fd_dir)
                for inode in inodes
            )
            if not owns_socket:
                continue
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                argv = [part.decode(errors="replace") for part in f.read().split(b"\0") if part]
            executable = os.path.basename(argv[0]) if argv else ""
            if executable in ("nc", "netcat") or any(os.path.basename(arg) in ("nc", "netcat") for arg in argv):
                matches.append(int(pid))
        except (FileNotFoundError, PermissionError, OSError):
            continue
    return matches


def wait_for_nc_listener(timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        matches = nc_listener_pids()
        if matches:
            return matches
        time.sleep(0.1)
    return []


def request_with_retry(url, timeout=5):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            return requests.get(url, timeout=2, headers={"Connection": "close"})
        except requests.exceptions.RequestException as error:
            last_error = error
            time.sleep(0.1)
    pytest.fail(f"Failed to connect to the HTTP server at {url}: {last_error}")


def test_http_server_response_multiple_sequential_requests():
    expected_sum = compute_expected_sum()
    url = "http://127.0.0.1:8080/"

    assert wait_for_nc_listener(), "No nc process is listening on 127.0.0.1:8080."

    # A one-shot listener will pass the first request but fail subsequent ones.
    for request_number in range(3):
        response = request_with_retry(url)
        assert response.status_code == 200, \
            f"Expected HTTP status 200 on request {request_number + 1}, but got {response.status_code}."
        body = response.text.strip()
        assert str(expected_sum) in body, \
            f"Expected the response body to contain '{expected_sum}', but got '{body}'."
        assert wait_for_nc_listener(), \
            f"The nc server did not resume listening after request {request_number + 1}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
