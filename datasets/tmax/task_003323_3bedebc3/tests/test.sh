#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import random
import signal
import subprocess
import tempfile
import time


def expected_output(lines):
    output = []
    previous_hash = None
    last_timestamp = None
    total = 0

    for line in lines:
        timestamp_text, sensor, value_text = line.split(",")
        timestamp = int(timestamp_text)
        value = int(value_text)
        digest = hashlib.sha256(f"{sensor}:{value_text}".encode()).digest()

        if digest == previous_hash:
            previous_hash = digest
            continue
        previous_hash = digest

        if last_timestamp is not None:
            fill_timestamp = last_timestamp + 10
            while fill_timestamp < timestamp:
                output.append({"t": fill_timestamp, "s": "FILL", "v": 0})
                fill_timestamp += 10

        output.append({"t": timestamp, "s": sensor, "v": value})
        total += value
        last_timestamp = timestamp

    output.append({"total_records": len(output), "sum": total})
    return output


def parse_cleaner_output(stdout):
    lines = stdout.splitlines()
    parsed = []
    for index, line in enumerate(lines):
        assert line.strip(), f"Blank output line at index {index}"
        try:
            item = json.loads(line)
        except json.JSONDecodeError as exc:
            raise AssertionError(f"Output line {index} is not valid JSON: {line!r}") from exc
        assert isinstance(item, dict), f"Output line {index} is not a JSON object"
        parsed.append(item)

    assert parsed, "Cleaner emitted no summary"
    for index, item in enumerate(parsed[:-1]):
        assert set(item) == {"t", "s", "v"}, f"Bad record keys at output line {index}: {item}"
        assert type(item["t"]) is int, f"Record timestamp must be an integer: {item}"
        assert type(item["s"]) is str, f"Record sensor must be a string: {item}"
        assert type(item["v"]) is int, f"Record value must be an integer: {item}"
    assert set(parsed[-1]) == {"total_records", "sum"}, f"Bad summary object: {parsed[-1]}"
    assert type(parsed[-1]["total_records"]) is int
    assert type(parsed[-1]["sum"]) is int
    return parsed


def run_cleaner(path, lines):
    input_data = "".join(line + "\n" for line in lines)
    proc = subprocess.run(
        [path], input=input_data, text=True, capture_output=True, timeout=15
    )
    assert proc.returncode == 0, f"{path} failed. Stderr: {proc.stderr}"
    return parse_cleaner_output(proc.stdout)


def test_cleaner_behavior_and_go_source():
    source_path = "/home/user/cleaner.go"
    agent_path = "/home/user/cleaner"

    assert os.path.isfile(source_path), f"Go source missing at {source_path}"
    assert os.path.isfile(agent_path), f"Agent binary missing at {agent_path}"
    assert os.access(agent_path, os.X_OK), f"Agent binary not executable at {agent_path}"

    rebuilt_path = "/tmp/cleaner-rebuilt"
    env = os.environ.copy()
    env["HOME"] = "/tmp/go-verifier-home"
    env["GOCACHE"] = "/tmp/go-verifier-cache"
    os.makedirs(env["HOME"], exist_ok=True)
    os.makedirs(env["GOCACHE"], exist_ok=True)
    build = subprocess.run(
        ["/usr/local/go/bin/go", "build", "-o", rebuilt_path, source_path],
        text=True,
        capture_output=True,
        env=env,
        timeout=60,
    )
    assert build.returncode == 0, f"cleaner.go does not build: {build.stderr}"

    cases = [
        [],
        ["1700000000,S1,10"],
        [
            "1700000000,S1,10",
            "1700000001,S1,10",
            "1700000002,S2,10",
            "1700000012,S2,11",
        ],
        [
            "100,A,-5",
            "110,B,3",
            "121,C,7",
            "142,D,-2",
        ],
        [
            "100,A,1",
            "100,A,1",
            "121,B,2",
            "121,B,2",
            "131,A,1",
        ],
    ]

    rng = random.Random(739184)
    sensors = ["S1", "S2", "TEMP_A", "HUMID_B", "X9"]
    for _ in range(60):
        timestamp = rng.randint(1000, 100000)
        lines = []
        previous = None
        for index in range(rng.randint(20, 250)):
            if previous is not None and index % 13 == 0:
                # A duplicate at the same timestamp avoids ambiguity while testing
                # stream-global adjacent-record deduplication.
                lines.append(previous)
                continue
            timestamp += rng.choice([1, 2, 5, 10, 11, 21, 35])
            sensor = rng.choice(sensors)
            value = rng.randint(-1000, 1000)
            previous = f"{timestamp},{sensor},{value}"
            lines.append(previous)
        cases.append(lines)

    for case_index, lines in enumerate(cases):
        expected = expected_output(lines)
        for executable in (agent_path, rebuilt_path):
            actual = run_cleaner(executable, lines)
            assert actual == expected, (
                f"Cleaner mismatch for case {case_index} using {executable}. "
                f"Expected preview: {expected[:8]!r}; actual preview: {actual[:8]!r}"
            )


def stop_legacy_server():
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/cmdline", "rb") as handle:
                command = handle.read()
            if b"/app/server.py" in command:
                os.kill(int(entry), signal.SIGTERM)
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    time.sleep(0.3)


def start_fixture_server(payload_path):
    server_code = r'''
import socket
import sys
payload = open(sys.argv[1], "rb").read()
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", 8080))
s.listen(10)
while True:
    conn, _ = s.accept()
    try:
        conn.sendall(payload)
    except OSError:
        pass
    finally:
        conn.close()
'''
    proc = subprocess.Popen(
        ["python3", "-c", server_code, payload_path],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
    )
    time.sleep(0.3)
    assert proc.poll() is None, f"Fixture TCP server failed: {proc.stderr.read()}"
    return proc


def restart_legacy_server():
    subprocess.Popen(
        ["python3", "/app/server.py"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


def test_pipeline_script():
    script_path = "/home/user/pipeline.sh"
    assert os.path.exists(script_path), f"{script_path} missing"
    assert os.access(script_path, os.X_OK), f"{script_path} not executable"

    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    timestamp = rng.randint(1800000000, 1900000000)
    stream_lines = []
    previous = None
    for index in range(501):
        if previous is not None and index % 19 == 0:
            line = previous
        else:
            timestamp += 21 if index % 23 == 0 else rng.randint(1, 6)
            line = f"{timestamp},P{rng.randint(1, 8)},{rng.randint(-50, 50)}"
            previous = line
        stream_lines.append(line)

    expected = expected_output(stream_lines[:500])
    payload_file = "/tmp/pipeline-stream.csv"
    with open(payload_file, "w") as handle:
        handle.write("\n".join(stream_lines) + "\n")

    stop_legacy_server()
    fixture_server = None
    try:
        fixture_server = start_fixture_server(payload_file)

        # Preserve the original fresh-run Redis assertion.
        subprocess.run(["redis-cli", "DEL", "sensor_data_cleaned"], check=True)

        proc = subprocess.run(
            [script_path], capture_output=True, text=True, timeout=90
        )
        assert proc.returncode == 0, f"pipeline.sh failed to execute. Stderr: {proc.stderr}"

        res = subprocess.run(
            ["redis-cli", "LLEN", "sensor_data_cleaned"],
            capture_output=True,
            text=True,
            check=True,
        )
        llen = int(res.stdout.strip())
        assert llen > 0, "Redis list 'sensor_data_cleaned' is empty after running pipeline.sh. Ensure it pipes output to Redis."

        stored_proc = subprocess.run(
            ["redis-cli", "--raw", "LRANGE", "sensor_data_cleaned", "0", "-1"],
            capture_output=True,
            text=True,
            check=True,
        )
        stored = parse_cleaner_output(stored_proc.stdout)
        assert len(stored) == len(expected), (
            f"Pipeline stored {len(stored)} lines, expected {len(expected)} from exactly 500 inputs"
        )
        assert stored == expected or stored == list(reversed(expected)), (
            "Redis contents are not the cleaner output produced from the first 500 TCP lines"
        )
    finally:
        if fixture_server is not None:
            fixture_server.terminate()
            try:
                fixture_server.wait(timeout=3)
            except subprocess.TimeoutExpired:
                fixture_server.kill()
        restart_legacy_server()


def test_cron_job():
    cron_file = "/var/spool/cron/crontabs/user"
    content = ""
    if os.path.exists(cron_file):
        with open(cron_file, "r") as f:
            content = f.read()
    else:
        res = subprocess.run(["crontab", "-u", "user", "-l"], capture_output=True, text=True)
        content = res.stdout

    assert "/home/user/pipeline.sh" in content, "Cron job for /home/user/pipeline.sh not found for user 'user'"

    found_every_minute = False
    for line in content.splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "/home/user/pipeline.sh" in line:
            parts = line.split()
            if parts[:5] == ["*", "*", "*", "*", "*"]:
                found_every_minute = True
                break

    assert found_every_minute, "Cron job is not scheduled to run every minute ('* * * * *')"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
