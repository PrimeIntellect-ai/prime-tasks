#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import math
import os
import random
import re
import string
import subprocess
import time
import urllib.request

ANALYZER = "/home/user/analyzer.py"


def generate_random_csv(num_lines, allow_record_newlines=True):
    chars = string.printable
    if not allow_record_newlines:
        chars = chars.replace("\n", "").replace("\r", "")
    out = io.StringIO()
    writer = csv.writer(out)
    for i in range(num_lines):
        event_id = f"evt_{i}_{random.randint(1000, 9999)}"
        timestamp = f"2023-10-10T10:00:{random.randint(10, 59)}Z"
        length = random.randint(0, 500)
        raw_text = "".join(random.choices(chars, k=length))
        writer.writerow([event_id, timestamp, raw_text])
    return out.getvalue()


def expected_rows(csv_input):
    rows = []
    window = []
    for row in csv.reader(io.StringIO(csv_input)):
        if not row:
            continue
        event_id = row[0]
        raw_text = row[2] if len(row) > 2 else ""
        normalized = re.sub(r"[^a-z0-9 ]", " ", raw_text.lower())
        normalized = re.sub(r" +", " ", normalized).strip()
        token_count = len(normalized.split(" ")) if normalized else 0

        if len(window) < 20:
            score = 0.0
        else:
            mean = sum(window) / 20.0
            variance = sum((value - mean) ** 2 for value in window) / 20.0
            std_dev = math.sqrt(variance)
            score = 0.0 if std_dev == 0 else abs(token_count - mean) / std_dev

        rows.append([event_id, str(token_count), f"{score:.4f}"])
        window.append(token_count)
        if len(window) > 20:
            window.pop(0)
    return rows


def parse_output(proc):
    assert proc.returncode == 0, f"Analyzer exited with {proc.returncode}: {proc.stderr}"
    return list(csv.reader(io.StringIO(proc.stdout)))


def analyzer_command():
    assert os.path.isfile(ANALYZER), f"Agent script missing at {ANALYZER}"

    with open(ANALYZER, "rb") as handle:
        first_line = handle.readline(256).decode("utf-8", "ignore").lower()

    candidates = []
    if os.access(ANALYZER, os.X_OK):
        candidates.append([ANALYZER])
    if first_line.startswith("#!"):
        if "python" in first_line:
            candidates.append(["python3", ANALYZER])
        elif "perl" in first_line:
            candidates.append(["perl", ANALYZER])
        elif "ruby" in first_line:
            candidates.append(["ruby", ANALYZER])
    candidates.extend([["python3", ANALYZER], ["perl", ANALYZER], ["ruby", ANALYZER]])

    unique = []
    for candidate in candidates:
        if candidate not in unique:
            unique.append(candidate)

    probe = io.StringIO()
    writer = csv.writer(probe)
    for i in range(25):
        writer.writerow([f"probe_{i}", "2023-10-10T10:00:00Z", "x " * (i % 7)])
    probe_input = probe.getvalue()
    expected = expected_rows(probe_input)

    for candidate in unique:
        try:
            proc = subprocess.run(candidate, input=probe_input, text=True,
                                  capture_output=True, timeout=10)
            if proc.returncode == 0 and list(csv.reader(io.StringIO(proc.stdout))) == expected:
                return candidate
        except (OSError, subprocess.TimeoutExpired, csv.Error):
            pass
    raise AssertionError("analyzer.py could not be run as a Python, Perl, or Ruby script")


def test_fuzz_equivalence():
    command = analyzer_command()
    random.seed(42)
    for i in range(500):
        num_lines = random.randint(50, 200)
        csv_input = generate_random_csv(num_lines)
        expected = expected_rows(csv_input)
        proc = subprocess.run(command, input=csv_input, text=True,
                              capture_output=True, timeout=15)
        actual = parse_output(proc)
        assert actual == expected, (
            f"Output mismatch on random input {i}.\n"
            f"Input preview:\n{csv_input[:200]}...\n"
            f"Expected preview:\n{expected[:5]}\n"
            f"Agent preview:\n{actual[:5]}"
        )


def wait_for_api(timeout=15):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            urllib.request.urlopen("http://localhost:5000/", timeout=0.5)
        except urllib.error.HTTPError:
            return
        except Exception:
            time.sleep(0.2)
        else:
            return
    raise AssertionError("API server did not start on port 5000")


def test_pipeline_orchestration():
    script_path = "/home/user/start_pipeline.sh"
    assert os.path.isfile(script_path), f"Pipeline script missing at {script_path}"

    subprocess.run(["pkill", "-f", "/app/api_server.py"], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-f", "/app/redis_forwarder.py"], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-f", r"tail.*\/tmp\/input_stream.csv"], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.5)
    for path in ("/tmp/input_stream.csv", "/tmp/output_stream.csv"):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    ping = subprocess.run(["redis-cli", "PING"], capture_output=True, text=True)
    assert ping.returncode == 0 and ping.stdout.strip() == "PONG", "Redis is not available"
    subprocess.run(["redis-cli", "DEL", "anomalies"], check=True,
                   stdout=subprocess.DEVNULL)

    subprocess.run(["bash", script_path], check=True, timeout=10)
    wait_for_api()

    random.seed(8675309)
    csv_data = generate_random_csv(100, allow_record_newlines=False)
    expected = [",".join(row) for row in expected_rows(csv_data)]
    req = urllib.request.Request(
        "http://localhost:5000/submit",
        data=csv_data.encode("utf-8"),
        headers={"Content-Type": "text/plain"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            assert response.status == 200
    except Exception as exc:
        raise AssertionError(f"Failed to POST to API server: {exc}")

    deadline = time.time() + 15
    lines = []
    while time.time() < deadline:
        redis_proc = subprocess.run(
            ["redis-cli", "--raw", "LRANGE", "anomalies", "0", "-1"],
            capture_output=True, text=True, check=True
        )
        lines = redis_proc.stdout.splitlines()
        if len(lines) >= 100:
            break
        time.sleep(0.2)

    assert len(lines) == 100, (
        f"Expected 100 lines in Redis 'anomalies' list, got {len(lines)}."
    )
    assert lines == expected, (
        "Redis contains lines that are not the analyzer's correct outputs.\n"
        f"Expected preview: {expected[:5]}\nActual preview: {lines[:5]}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
