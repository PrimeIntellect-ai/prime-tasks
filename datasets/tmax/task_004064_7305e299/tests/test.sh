#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "bs4:beautifulsoup4"; do
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
import os
import random
import re
import subprocess
import tempfile
import time
import urllib.request

import pytest
import redis
from bs4 import BeautifulSoup

TOOL = "/home/user/log_tool"
SERVICES_STARTED = False


def test_nginx_config_updated():
    conf_path = "/home/user/nginx.conf"
    assert os.path.isfile(conf_path), f"Nginx config not found at {conf_path}"
    with open(conf_path, "r") as f:
        content = f.read()
    assert "listen 8080;" in content, "Nginx config not updated to listen on 8080"
    assert "root /home/user/reports;" in content, "Nginx config root not updated to /home/user/reports"


def test_log_tool_exists():
    assert os.path.isfile(TOOL), f"Executable not found at {TOOL}"
    assert os.access(TOOL, os.X_OK), f"File at {TOOL} is not executable"
    with open(TOOL, "rb") as f:
        assert f.read(4) == b"\x7fELF", "log_tool is not a compiled ELF executable"


def run_filter(input_bytes):
    with tempfile.TemporaryDirectory() as td:
        in_path = os.path.join(td, "input.csv")
        out_path = os.path.join(td, "output.csv")
        with open(in_path, "wb") as f:
            f.write(input_bytes)
        subprocess.run([TOOL, "--filter", in_path, out_path], check=True, timeout=10)
        assert os.path.isfile(out_path), "Filter did not create its requested output file"
        with open(out_path, "rb") as f:
            return f.read()


def test_adversarial_corpus():
    clean_dir = "/app/corpora/clean"
    evil_dir = "/app/corpora/evil"

    clean_failed = []
    for name in os.listdir(clean_dir):
        if not name.endswith(".csv"):
            continue
        path = os.path.join(clean_dir, name)
        with open(path, "rb") as f:
            original = f.read()
        if run_filter(original) != original:
            clean_failed.append(name)

    evil_failed = []
    for name in os.listdir(evil_dir):
        if not name.endswith(".csv"):
            continue
        path = os.path.join(evil_dir, name)
        with open(path, "rb") as f:
            original = f.read()
        if run_filter(original) != b"":
            evil_failed.append(name)

    assert not clean_failed, f"{len(clean_failed)} clean corpora modified/failed: {', '.join(clean_failed)}"
    assert not evil_failed, f"{len(evil_failed)} evil corpora bypassed: {', '.join(evil_failed)}"


def random_case(text, rng):
    return "".join(c.upper() if c.isalpha() and rng.randrange(2) else c.lower() if c.isalpha() else c for c in text)


def test_generated_mixed_filter_cases():
    rng = random.SystemRandom()
    nonce = os.urandom(8).hex()
    rows = []
    expected = []

    for i in range(9):
        line = f"{1700000000+i},clean_{nonce}_{i},{rng.randrange(-150, 500)/10:.1f},status_{os.urandom(5).hex()}\n"
        rows.append(line)
        expected.append(line)

    triggers = ["<script>", "javascript:", "UNION SELECT", "onload="]
    for i, trigger in enumerate(triggers):
        payload = f"prefix_{os.urandom(4).hex()}_{random_case(trigger, rng)}_suffix_{os.urandom(4).hex()}"
        rows.append(f"{1700000100+i},bad_{nonce}_{i},{rng.randrange(0, 500)/10:.1f},{payload}\n")

    rng.shuffle(rows)
    clean_set = set(expected)
    expected_in_input_order = "".join(row for row in rows if row in clean_set).encode()
    actual = run_filter("".join(rows).encode())
    assert actual == expected_in_input_order, "Generated mixed input was not filtered case-insensitively while preserving clean rows exactly"


def start_services_once():
    global SERVICES_STARTED
    if SERVICES_STARTED:
        return
    subprocess.run(["redis-cli", "shutdown", "nosave"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    subprocess.run(["pkill", "-x", "nginx"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    time.sleep(0.3)
    subprocess.run(["/app/start_services.sh"], check=True, timeout=10)
    time.sleep(1)
    SERVICES_STARTED = True


def push_and_wait_consumed(client, record, timeout=3):
    client.lpush("raw_logs", record)
    deadline = time.time() + timeout
    while time.time() < deadline:
        if client.llen("raw_logs") == 0:
            return
        time.sleep(0.02)
    pytest.fail("Daemon did not consume a Redis record")


def fetch_report():
    req = urllib.request.Request("http://localhost:8080/index.html")
    with urllib.request.urlopen(req, timeout=3) as response:
        return response.read().decode("utf-8")


def launch_clean_daemon():
    start_services_once()
    client = redis.Redis(host="localhost", port=6379, db=0, decode_responses=True)
    client.flushdb()
    report = "/home/user/reports/index.html"
    try:
        os.remove(report)
    except FileNotFoundError:
        pass
    proc = subprocess.Popen([TOOL, "--daemon"])
    time.sleep(0.5)
    assert proc.poll() is None, "log_tool exited instead of running continuously in daemon mode"
    return client, proc


def stop_daemon(proc):
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=3)


def test_end_to_end_daemon():
    client, tool_proc = launch_clean_daemon()
    try:
        records = [
            "1000000010,sensor_B,20.0,ok",
            "1000000020,sensor_A,10.0,ok",
            "1000000030,sensor_C,30.0,ok",
            "1000000040,sensor_D,40.0,<script>",
        ]
        for record in records:
            push_and_wait_consumed(client, record)
        push_and_wait_consumed(client, "1000000060,sensor_A,15.0,ok")

        deadline = time.time() + 8
        html = None
        while time.time() < deadline:
            try:
                candidate = fetch_report()
                if "sensor_A" in candidate and "sensor_C" in candidate:
                    html = candidate
                    break
            except Exception:
                pass
            time.sleep(0.1)
        assert html is not None, "Failed to fetch completed report from Nginx"

        soup = BeautifulSoup(html, "html.parser")
        h1 = soup.find("h1")
        assert h1 is not None, "Missing <h1> tag in report"
        assert "1000000000" in h1.text or "1000000010" in h1.text, "Bucket timestamp not found in <h1>"

        p = soup.find("p")
        assert p is not None, "Missing <p> tag for temperatures"
        assert "30.0" in p.text, "Max temperature incorrect or missing"
        assert "10.0" in p.text, "Min temperature incorrect or missing"

        ul = soup.find("ul")
        assert ul is not None, "Missing <ul> tag for events"
        lis = ul.find_all("li")
        assert len(lis) == 3, f"Expected 3 valid events in list, got {len(lis)}"
        assert "sensor_A" in lis[0].text, "First element should be sensor_A"
        assert "sensor_B" in lis[1].text, "Second element should be sensor_B"
        assert "sensor_C" in lis[2].text, "Third element should be sensor_C"
        assert "sensor_D" not in html, "Malicious record was not filtered out"
        assert tool_proc.poll() is None, "Daemon exited before completing continuous processing"
    finally:
        stop_daemon(tool_proc)


def test_generated_daemon_aggregation():
    rng = random.SystemRandom()
    client, tool_proc = launch_clean_daemon()
    try:
        bucket = rng.randrange(20000000, 30000000) * 60
        nonce = os.urandom(5).hex()
        count = rng.randrange(5, 9)
        valid = []
        for i in range(count):
            sensor = f"sensor_{rng.randrange(10000, 99999)}_{nonce}_{i}"
            temp = rng.randrange(-200, 700) / 10.0
            metadata = f"meta_{nonce}_{os.urandom(3).hex()}"
            timestamp = bucket + rng.randrange(1, 55)
            valid.append((timestamp, sensor, temp, metadata))

        records = [f"{ts},{sensor},{temp:.1f},{meta}" for ts, sensor, temp, meta in valid]
        malicious_ids = []
        for i, trigger in enumerate(["<script>", "javascript:", "UNION SELECT", "onload="]):
            sensor = f"blocked_{nonce}_{i}"
            malicious_ids.append(sensor)
            payload = f"x{random_case(trigger, rng)}{os.urandom(3).hex()}"
            records.append(f"{bucket+rng.randrange(1,55)},{sensor},{rng.randrange(800,999)/10:.1f},{payload}")
        rng.shuffle(records)

        for record in records:
            push_and_wait_consumed(client, record)
        trigger_sensor = f"next_{nonce}"
        push_and_wait_consumed(client, f"{bucket+60},{trigger_sensor},1.0,next_bucket")

        deadline = time.time() + 8
        html = None
        while time.time() < deadline:
            try:
                candidate = fetch_report()
                if str(bucket) in candidate and all(sensor in candidate for _, sensor, _, _ in valid):
                    html = candidate
                    break
            except Exception:
                pass
            time.sleep(0.1)
        assert html is not None, "Randomized bucket report was not generated and served"

        soup = BeautifulSoup(html, "html.parser")
        h1 = soup.find("h1")
        assert h1 is not None and h1.get_text(strip=True) == f"Bucket: {bucket}", "Incorrect one-minute bucket start"

        p = soup.find("p")
        assert p is not None, "Missing max/min paragraph"
        numbers = [float(x) for x in re.findall(r"[-+]?\d+(?:\.\d+)?", p.get_text(" ", strip=True))]
        assert len(numbers) >= 2, "Max/min temperatures are not numeric"
        assert abs(numbers[0] - max(v[2] for v in valid)) < 1e-6, "Randomized maximum temperature is incorrect"
        assert abs(numbers[1] - min(v[2] for v in valid)) < 1e-6, "Randomized minimum temperature is incorrect"

        ul = soup.find("ul")
        assert ul is not None, "Missing event list"
        items = ul.find_all("li")
        assert len(items) == len(valid), "Report did not contain exactly all sanitized events"
        expected = sorted(valid, key=lambda item: item[1])
        for li, (_, sensor, temp, metadata) in zip(items, expected):
            text = li.get_text(" ", strip=True)
            assert sensor in text, "Events are not sorted by sensor_id"
            assert metadata in text, "Event metadata is missing from the generated template"
            match = re.search(r":\s*([-+]?\d+(?:\.\d+)?)\s*-", text)
            assert match and abs(float(match.group(1)) - temp) < 1e-6, "Event temperature is incorrect"

        for sensor in malicious_ids:
            assert sensor not in html, "A randomized malicious daemon record bypassed sanitization"
        assert trigger_sensor not in html, "The next-minute trigger was included in the finalized prior bucket"
        assert tool_proc.poll() is None, "Daemon exited instead of continuing to consume Redis records"
    finally:
        stop_daemon(tool_proc)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
