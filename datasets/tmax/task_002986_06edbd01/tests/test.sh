#!/bin/bash
mkdir -p /logs/verifier
status=0
router=/app/legacy_router
original=/app/.legacy_router.verifier-original
log=/tmp/legacy_router_invocations.log
challenges=/tmp/legacy_router_challenges.txt

cleanup() {
    if [ -e "$original" ]; then
        rm -f "$router"
        mv "$original" "$router"
        chmod +x "$router"
    fi
    rm -f "$challenges"
}
trap cleanup EXIT

if [ ! -f "$router" ] || [ ! -x "$router" ]; then
    status=1
else
    rm -f "$original" "$log" "$challenges"
    if ! mv "$router" "$original"; then
        status=1
    else
        cat > "$router" <<'WRAPPER_EOF'
#!/usr/bin/env python3
import fcntl
import os
import struct
import subprocess
import sys

ORIGINAL = "/app/.legacy_router.verifier-original"
LOG = "/tmp/legacy_router_invocations.log"
CHALLENGES = "/tmp/legacy_router_challenges.txt"

data = sys.stdin.buffer.read()
fd = os.open(LOG, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o666)
try:
    fcntl.flock(fd, fcntl.LOCK_EX)
    os.write(fd, (f"{len(data)}:{data.hex()}\n").encode("ascii"))
finally:
    os.close(fd)

if len(data) != 8:
    sys.exit(2)

result = subprocess.run([ORIGINAL], input=data, stdout=subprocess.PIPE,
                        stderr=subprocess.DEVNULL, timeout=5, check=False)
if result.returncode != 0 or len(result.stdout) != 4:
    sys.exit(3)

output = result.stdout
try:
    key = data.hex()
    with open(CHALLENGES, "r", encoding="ascii") as f:
        for line in f:
            fields = line.strip().split()
            if len(fields) == 2 and fields[0] == key:
                output = bytes.fromhex(fields[1])
                break
except FileNotFoundError:
    pass

sys.stdout.buffer.write(output)
sys.stdout.buffer.flush()
WRAPPER_EOF
        chmod 755 "$router"
        touch "$log"
        chmod 666 "$log"
    fi
fi

cat > /tmp/test_final_state.py <<'TEST_EOF'
import os
import re
import secrets
import struct
import subprocess
import tempfile

import pytest
import requests

URL = "http://127.0.0.1:9000/route"
LOG = "/tmp/legacy_router_invocations.log"
CHALLENGES = "/tmp/legacy_router_challenges.txt"


def compute_expected(source: int, dest: int) -> int:
    val = (source ^ dest) + (source * 31) - (dest * 7)
    return val & 0xFFFFFFFF


def read_log():
    with open(LOG, "r", encoding="ascii") as f:
        return [line.strip() for line in f if line.strip()]


def assert_one_invocation(before, source, dest):
    after = read_log()
    assert len(after) == len(before) + 1, \
        "Each /route request must execute /app/legacy_router exactly once"
    expected = struct.pack("<II", source, dest).hex()
    assert after[-1] == f"8:{expected}", \
        "legacy_router did not receive exactly the requested two little-endian uint32 values"
    return after


def post_and_check(source, dest, expected):
    before = read_log()
    try:
        response = requests.post(
            URL, json={"source": source, "destination": dest}, timeout=5
        )
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to {URL} or request timed out: {exc}")

    assert response.status_code == 200, \
        f"Expected status code 200, got {response.status_code}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")
    assert "next_hop" in data, f"Response JSON missing 'next_hop' key: {data}"
    assert data["next_hop"] == expected, \
        f"Expected next_hop {expected}, got {data['next_hop']}"
    assert_one_invocation(before, source, dest)


def test_bench_file_exists_and_is_raw_valid_output():
    path = "/home/user/bench.txt"
    assert os.path.exists(path), f"{path} does not exist. Did you run the benchmark?"
    assert os.path.isfile(path), f"{path} is not a file."
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        content = f.read()

    # Accept complete raw output from either Apache Bench or wrk, rather than a
    # file containing only a convenient keyword.
    ab_concurrency = re.search(r"(?mi)^Concurrency Level:\s*(\d+)\s*$", content)
    ab_complete = re.search(r"(?mi)^Complete requests:\s*(\d+)\s*$", content)
    ab_failed = re.search(r"(?mi)^Failed requests:\s*(\d+)\s*$", content)
    ab_rate = re.search(r"(?mi)^Requests per second:\s*[0-9.]+", content)
    ab_time = re.search(r"(?mi)^Time taken for tests:\s*[0-9.]+", content)
    if all((ab_concurrency, ab_complete, ab_failed, ab_rate, ab_time)):
        assert int(ab_concurrency.group(1)) == 10
        assert int(ab_complete.group(1)) >= 100
        assert int(ab_failed.group(1)) == 0
        non_2xx = re.search(r"(?mi)^Non-2xx responses:\s*(\d+)\s*$", content)
        assert non_2xx is None or int(non_2xx.group(1)) == 0
        return

    wrk_config = re.search(r"(?mi)^\s*(\d+) threads and (\d+) connections\s*$", content)
    wrk_total = re.search(r"(?mi)^\s*(\d+) requests in\s+", content)
    wrk_rate = re.search(r"(?mi)^Requests/sec:\s*[0-9.]+", content)
    wrk_running = re.search(r"(?mi)^Running\s+.+\s+test\s+@\s+http", content)
    assert all((wrk_config, wrk_total, wrk_rate, wrk_running)), \
        f"{path} is not recognizable complete raw ab or wrk output"
    assert int(wrk_config.group(2)) == 10
    assert int(wrk_total.group(1)) >= 100


def test_http_route_endpoint_and_real_binary_use():
    # Preserve the original fixed behavioral assertions.
    open(CHALLENGES, "w").close()
    for source, dest in [
        (100, 200),
        (12345, 67890),
        (0, 0),
        (4294967295, 4294967295),
    ]:
        post_and_check(source, dest, compute_expected(source, dest))

    # Hidden, per-verification inputs prevent a fixed response table. For these
    # calls the instrumentation returns a verifier-selected value after running
    # the real binary; this also proves the service consumes the child output
    # rather than merely launching a dummy process and recomputing the formula.
    cases = []
    seen = set()
    while len(cases) < 16:
        source = secrets.randbits(32)
        dest = secrets.randbits(32)
        if (source, dest) in seen:
            continue
        seen.add((source, dest))
        expected = secrets.randbits(32)
        cases.append((source, dest, expected))

    with open(CHALLENGES, "w", encoding="ascii") as f:
        for source, dest, expected in cases:
            key = struct.pack("<II", source, dest).hex()
            value = struct.pack("<I", expected).hex()
            f.write(f"{key} {value}\n")

    for source, dest, expected in cases:
        post_and_check(source, dest, expected)

    open(CHALLENGES, "w").close()


def test_100_request_concurrency_10_run_reaches_binary_each_time():
    source = secrets.randbits(32)
    dest = secrets.randbits(32)
    body = ('{"source":%d,"destination":%d}' % (source, dest)).encode("ascii")
    before = read_log()

    with tempfile.NamedTemporaryFile() as payload:
        payload.write(body)
        payload.flush()
        proc = subprocess.run(
            ["ab", "-n", "100", "-c", "10", "-s", "10", "-p", payload.name,
             "-T", "application/json", URL],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
            timeout=60, check=False,
        )

    assert proc.returncode == 0, f"Independent ab run failed:\n{proc.stdout}"
    assert re.search(r"(?mi)^Concurrency Level:\s*10\s*$", proc.stdout)
    assert re.search(r"(?mi)^Complete requests:\s*100\s*$", proc.stdout)
    assert re.search(r"(?mi)^Failed requests:\s*0\s*$", proc.stdout)
    non_2xx = re.search(r"(?mi)^Non-2xx responses:\s*(\d+)\s*$", proc.stdout)
    assert non_2xx is None or int(non_2xx.group(1)) == 0

    after = read_log()
    new = after[len(before):]
    expected_entry = "8:" + struct.pack("<II", source, dest).hex()
    assert len(new) == 100, \
        f"100 HTTP requests caused {len(new)} legacy_router executions, expected exactly 100"
    assert all(entry == expected_entry for entry in new), \
        "Benchmark requests were not serialized correctly for legacy_router"
TEST_EOF

if [ "$status" -eq 0 ]; then
    if ! python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short; then
        status=1
    fi
fi

cleanup
trap - EXIT
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
