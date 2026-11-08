#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import math
import os
import random
import socket
import subprocess
import time
import urllib.error
import urllib.request
import uuid

import pytest

PROJECT = "/home/user/ingest_api"
SOURCE = os.path.join(PROJECT, "main.go")
BINARY = "/tmp/ingest_api_submission"
PROXY_URL = "http://127.0.0.1:8080/upload"


def post_bytes(url: str, content: bytes, filename=None) -> int:
    boundary = uuid.uuid4().hex
    filename = filename or f"{uuid.uuid4().hex}.csv"
    headers = {"Content-type": f"multipart/form-data; boundary={boundary}"}
    body = (
        f"--{boundary}\r\n"
        f'Content-Disposition: form-data; name="file"; filename="{filename}"\r\n'
        f"Content-Type: text/csv\r\n\r\n"
    ).encode() + content + f"\r\n--{boundary}--\r\n".encode()
    req = urllib.request.Request(url, data=body, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            return response.status
    except urllib.error.HTTPError as exc:
        return exc.code
    except Exception:
        return 500


def post_csv(url: str, file_path: str) -> int:
    with open(file_path, "rb") as handle:
        return post_bytes(url, handle.read(), os.path.basename(file_path))


def make_csv(rows) -> bytes:
    output = io.StringIO(newline="")
    writer = csv.writer(output, lineterminator="\n")
    writer.writerow(["transaction_id", "timestamp", "category", "amount"])
    writer.writerows(rows)
    return output.getvalue().encode()


def historical_values():
    values = {}
    with open("/app/data/historical.csv", newline="") as handle:
        reader = csv.DictReader(handle)
        assert reader.fieldnames == ["transaction_id", "timestamp", "category", "amount"]
        for row in reader:
            values.setdefault(row["category"], []).append(float(row["amount"]))
    assert values
    return values


def redis_get(key):
    result = subprocess.run(
        ["redis-cli", "--raw", "GET", key],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )
    assert result.returncode == 0, result.stderr
    value = result.stdout.rstrip("\r\n")
    return None if value == "" else value


def listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as handle:
                next(handle)
                for line in handle:
                    fields = line.split()
                    local_port = int(fields[1].rsplit(":", 1)[1], 16)
                    if local_port == port and fields[3] == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
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
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(name))
                    break
        except (FileNotFoundError, PermissionError):
            continue
    return pids


def wait_for_service(process, expected):
    deadline = time.time() + 15
    while time.time() < deadline:
        if process.poll() is not None:
            pytest.fail(f"The built Go service exited with status {process.returncode}")
        try:
            with socket.create_connection(("127.0.0.1", 9000), timeout=0.25):
                populated = True
                for category in expected:
                    if redis_get(f"ci_lower_{category}") is None or redis_get(f"ci_upper_{category}") is None:
                        populated = False
                        break
                if populated:
                    return
        except OSError:
            pass
        time.sleep(0.15)
    pytest.fail("The submitted Go service did not listen on port 9000 and populate Redis")


@pytest.fixture(scope="session", autouse=True)
def run_submitted_application():
    assert os.path.isfile(SOURCE), f"Missing required Go source file: {SOURCE}"
    assert not os.path.islink(SOURCE), "main.go must be a regular submitted source file"
    assert os.path.getsize(SOURCE) > 0, "main.go is empty"

    build = subprocess.run(
        ["go", "build", "-o", BINARY, SOURCE],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=90,
    )
    assert build.returncode == 0, f"main.go did not build:\n{build.stdout}"

    for pid in listener_pids(9000):
        try:
            os.kill(pid, 15)
        except ProcessLookupError:
            pass
    deadline = time.time() + 5
    while listener_pids(9000) and time.time() < deadline:
        time.sleep(0.1)
    for pid in listener_pids(9000):
        try:
            os.kill(pid, 9)
        except ProcessLookupError:
            pass

    flushed = subprocess.run(["redis-cli", "FLUSHDB"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
    assert flushed.returncode == 0, "Could not clear Redis before testing startup population"

    process = subprocess.Popen(
        [BINARY],
        cwd=PROJECT,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    values = historical_values()
    wait_for_service(process, values)

    # Replace the contradictory empty setup corpus with a valid clean sample and
    # an actually invalid sample while retaining the original corpus assertions.
    first_category = next(iter(values))
    baseline = sum(values[first_category]) / len(values[first_category])
    os.makedirs("/app/eval/corpus/clean", exist_ok=True)
    os.makedirs("/app/eval/corpus/evil", exist_ok=True)
    with open("/app/eval/corpus/clean/1.csv", "wb") as handle:
        handle.write(make_csv([["clean", "1700000000", first_category, repr(baseline)]]))
    with open("/app/eval/corpus/evil/1.csv", "wb") as handle:
        handle.write(b"transaction_id,timestamp,category,amount\nbad,1700000000,A,not-a-number\n")

    yield
    # Deliberately leave the verified service running, as required by the task.


def test_ready_file_exists():
    assert os.path.exists("/home/user/ready.txt"), "The /home/user/ready.txt file was not created by the agent."
    with open("/home/user/ready.txt") as handle:
        assert handle.read().strip() == "READY", "ready.txt must contain READY"


def test_redis_confidence_intervals():
    values = historical_values()
    for category, amounts in values.items():
        lower_raw = redis_get(f"ci_lower_{category}")
        upper_raw = redis_get(f"ci_upper_{category}")
        assert lower_raw is not None, f"Missing ci_lower_{category} in Redis"
        assert upper_raw is not None, f"Missing ci_upper_{category} in Redis"
        lower = float(lower_raw)
        upper = float(upper_raw)
        assert math.isfinite(lower) and math.isfinite(upper)
        assert lower <= upper
        # Every supplied historical category has one observation, so all 1000
        # bootstrap means and both required percentiles equal that observation.
        if len(amounts) == 1:
            assert math.isclose(lower, amounts[0], rel_tol=1e-12, abs_tol=1e-9)
            assert math.isclose(upper, amounts[0], rel_tol=1e-12, abs_tol=1e-9)


def test_adversarial_corpus():
    clean_dir = "/app/eval/corpus/clean"
    evil_dir = "/app/eval/corpus/evil"
    assert os.path.isdir(clean_dir), f"Clean corpus directory missing at {clean_dir}"
    assert os.path.isdir(evil_dir), f"Evil corpus directory missing at {evil_dir}"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith(".csv")]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith(".csv")]
    assert clean_files, "Clean corpus contains no CSV files"
    assert evil_files, "Evil corpus contains no CSV files"

    clean_failures = []
    evil_failures = []
    for path in clean_files:
        status = post_csv(PROXY_URL, path)
        if status != 200:
            clean_failures.append(f"{os.path.basename(path)} (status {status})")
    for path in evil_files:
        status = post_csv(PROXY_URL, path)
        if status != 406:
            evil_failures.append(f"{os.path.basename(path)} (status {status})")

    errors = []
    if evil_failures:
        errors.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed: {', '.join(evil_failures)}")
    if clean_failures:
        errors.append(f"{len(clean_failures)} of {len(clean_files)} clean rejected: {', '.join(clean_failures)}")
    if errors:
        pytest.fail(" | ".join(errors))


def test_randomized_schema_aggregation_and_anomaly_checks():
    values = historical_values()
    baselines = {category: sum(amounts) / len(amounts) for category, amounts in values.items()}
    categories = list(baselines)
    cases = []

    # Valid individual and combined-category files.
    for index, (category, amount) in enumerate(baselines.items()):
        cases.append((200, make_csv([[f"v{index}", str(1800000000 + index), category, repr(amount)]])))
    combined = [[f"all{i}", str(1810000000 + i), category, repr(amount)]
                for i, (category, amount) in enumerate(baselines.items())]
    cases.append((200, make_csv(combined)))

    # Validation is based on each uploaded category mean, not individual rows.
    category = categories[0]
    amount = baselines[category]
    delta = max(1.0, abs(amount) * 0.1)
    cases.append((200, make_csv([
        ["mean-low", "1820000000", category, repr(amount - delta)],
        ["mean-high", "1820000001", category, repr(amount + delta)],
    ])))

    # Statistically invalid and unknown categories.
    for index, (category, amount) in enumerate(baselines.items()):
        offset = max(1.0, abs(amount) * 0.2)
        cases.append((406, make_csv([[f"high{index}", "1830000000", category, repr(amount + offset)]])))
        cases.append((406, make_csv([[f"low{index}", "1830000001", category, repr(amount - offset)]])))
    cases.append((406, make_csv([["unknown", "1840000000", f"UNKNOWN_{uuid.uuid4().hex}", "1.0"]])))

    # Empty, header-only, malformed-schema, wrong-type, short, and extra-column inputs.
    cases.extend([
        (406, b""),
        (406, b"transaction_id,timestamp,category,amount\n"),
        (406, b"timestamp,transaction_id,category,amount\n1850000000,x,A,100.5\n"),
        (406, b"transaction_id,timestamp,category,amount\nx,not-an-int,A,100.5\n"),
        (406, b"transaction_id,timestamp,category,amount\nx,1850000000,A,not-a-float\n"),
        (406, b"transaction_id,timestamp,category,amount\nx,1850000000,A\n"),
        (406, b"transaction_id,timestamp,category,amount\nx,1850000000,A,100.5,extra\n"),
        (406, b'transaction_id,timestamp,category,amount\n"unterminated,1850000000,A,100.5\n'),
    ])

    random.SystemRandom().shuffle(cases)
    failures = []
    for expected, content in cases:
        status = post_bytes(PROXY_URL, content)
        if status != expected:
            failures.append(f"expected {expected}, got {status}")
    assert not failures, "; ".join(failures)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
