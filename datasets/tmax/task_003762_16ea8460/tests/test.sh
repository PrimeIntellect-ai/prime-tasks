#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import signal
import subprocess
import time
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import urlopen

import pytest

BASE_URL = "http://127.0.0.1:8080/api/v1/anomalies"
REQUIRED_KEYS = {"timestamp", "machine_id", "temperature", "sensor_reading", "status_notes"}


def fetch_anomalies(machine_id: str):
    try:
        url = BASE_URL + "?" + urlencode({"id": machine_id})
        with urlopen(url, timeout=5) as response:
            assert response.status == 200, f"Expected HTTP 200 for {machine_id}, got {response.status}"
            return json.loads(response.read().decode("utf-8"))
    except Exception as exc:
        pytest.fail(f"Failed to fetch valid JSON for machine {machine_id}: {exc}")


def assert_exact_keys(record):
    assert isinstance(record, dict), "Each array entry must be a JSON object"
    assert set(record.keys()) == REQUIRED_KEYS, (
        f"Record keys must be exactly {sorted(REQUIRED_KEYS)}, got {sorted(record.keys())}"
    )


def test_a73b_records():
    data = fetch_anomalies("A73B")
    assert isinstance(data, list), "Response must be a JSON array"
    assert len(data) == 1, f"Expected exactly 1 record for A73B, got {len(data)}"
    record = data[0]
    assert_exact_keys(record)
    assert record.get("timestamp") == "2023-10-01T10:00:00Z"
    assert record.get("machine_id") == "A73B"
    assert float(record.get("temperature")) == 45.2
    assert str(record.get("sensor_reading")) == "100"
    assert record.get("status_notes") == "Normal operation"


def test_d90e_records():
    data = fetch_anomalies("D90E")
    assert isinstance(data, list), "Response must be a JSON array"
    assert len(data) == 1, f"Expected exactly 1 record for D90E, got {len(data)}"
    record = data[0]
    assert_exact_keys(record)
    assert record.get("timestamp") == "2023-10-01T10:10:00Z"
    assert record.get("machine_id") == "D90E"
    assert float(record.get("temperature")) == 10.5
    assert str(record.get("sensor_reading")) == "50"
    assert record.get("status_notes") == "System offline due to résumé"


def test_o22x_records():
    data = fetch_anomalies("O22X")
    assert isinstance(data, list), "Response must be a JSON array"
    assert len(data) == 1, f"Expected exactly 1 record for O22X, got {len(data)}"
    record = data[0]
    assert_exact_keys(record)
    assert record.get("timestamp") == "2023-10-01T10:15:00Z"
    assert record.get("machine_id") == "O22X"
    assert float(record.get("temperature")) == -10.0
    assert str(record.get("sensor_reading")) == "10"
    assert record.get("status_notes") == "Cold start"


def listener_pid():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) < 10 or fields[3] != "0A":
                continue
            host, port = fields[1].rsplit(":", 1)
            if int(port, 16) != 8080:
                continue
            # For IPv4, require an exact 127.0.0.1 listener as instructed.
            if table.endswith("tcp") and host != "0100007F":
                continue
            inodes.add(fields[9])
    assert inodes, "No process is listening on 127.0.0.1:8080"

    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / "fd").iterdir():
                target = os.readlink(fd)
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    return int(proc.name)
        except (OSError, PermissionError):
            continue
    pytest.fail("Could not identify the server process")


def capture_server(pid):
    proc = Path(f"/proc/{pid}")
    cmdline = (proc / "cmdline").read_bytes().split(b"\0")
    cmdline = [part for part in cmdline if part]
    assert cmdline, "The server process has no restartable command line"
    cwd = os.readlink(proc / "cwd")
    status = (proc / "status").read_text()
    uid = int(next(line for line in status.splitlines() if line.startswith("Uid:" )).split()[1])
    gid = int(next(line for line in status.splitlines() if line.startswith("Gid:" )).split()[1])
    env = {}
    for item in (proc / "environ").read_bytes().split(b"\0"):
        if b"=" in item:
            key, value = item.split(b"=", 1)
            env[key] = value
    return cmdline, cwd, uid, gid, env


def restart_server(pid, launch):
    cmdline, cwd, uid, gid, env = launch
    os.kill(pid, signal.SIGTERM)
    for _ in range(30):
        if not Path(f"/proc/{pid}").exists():
            break
        time.sleep(0.1)
    if Path(f"/proc/{pid}").exists():
        os.kill(pid, signal.SIGKILL)
        time.sleep(0.2)

    def demote():
        os.setsid()
        if os.geteuid() == 0:
            os.setgroups([])
            os.setgid(gid)
            os.setuid(uid)

    log = open("/tmp/restarted_server.log", "wb")
    child = subprocess.Popen(
        cmdline, cwd=cwd, env=env, stdin=subprocess.DEVNULL,
        stdout=log, stderr=subprocess.STDOUT, preexec_fn=demote
    )
    for _ in range(80):
        if child.poll() is not None:
            log.flush()
            details = Path("/tmp/restarted_server.log").read_text(errors="replace")
            pytest.fail(f"Server exited after restart with code {child.returncode}: {details}")
        try:
            with urlopen(BASE_URL + "?id=readiness-check", timeout=0.25) as response:
                if response.status == 200:
                    return
        except Exception:
            time.sleep(0.1)
    pytest.fail("Restarted service did not begin listening on 127.0.0.1:8080")


def make_machine_ids():
    words = {
        "B": "bravo", "C": "charlie", "F": "foxtrot", "G": "golf",
        "K": "kilo", "L": "lima", "M": "mike", "P": "papa",
        "Q": "quebec", "R": "romeo", "S": "sierra", "T": "tango",
        "V": "victor", "W": "whiskey", "Y": "yankee", "Z": "zulu"
    }
    number_words = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "niner"]
    letters = list(words)
    ids = []
    spoken = []
    while len(ids) < 3:
        a, b = secrets.choice(letters), secrets.choice(letters)
        d1, d2 = secrets.randbelow(10), secrets.randbelow(10)
        machine_id = f"{a}{d1}{d2}{b}"
        if machine_id in ids or machine_id in {"A73B", "D90E", "O22X", "X99Y"}:
            continue
        ids.append(machine_id)
        spoken.append(f"{words[a]} {number_words[d1]} {number_words[d2]} {words[b]}")
    return ids, spoken


def test_pipeline_on_runtime_generated_inputs():
    pid = listener_pid()
    launch = capture_server(pid)
    ids, spoken = make_machine_ids()
    rng = random.SystemRandom()
    temp_early = round(rng.uniform(-35.0, 35.0), 3)
    temp_late = round(rng.uniform(40.0, 120.0), 3)
    temp_third = round(rng.uniform(1.0, 99.0), 3)
    sensors = [str(rng.randrange(1000, 9999)) for _ in range(5)]

    phrase = "The following machines require immediate inspection: " + ", ".join(spoken[:-1]) + ", and " + spoken[-1] + "."
    subprocess.run(["espeak", "-w", "/app/anomalies.wav", phrase], check=True)

    rows = [
        b"timestamp,machine_id,temperature,sensor_reading,status_notes\n",
        f"2026-04-03T12:00:00Z,{ids[0]},{temp_late},{sensors[0]},Caf".encode() + b"\xe9 r\xe9sum\xe9\n",
        f"2026-04-03T12:00:00Z,{ids[0]},99.9,999999,Duplicate must be ignored\n".encode(),
        f"2026-04-03T11:00:00Z,{ids[0]},{temp_early},{sensors[1]},Earlier record\n".encode(),
        f"2026-04-03T13:00:00Z,{ids[0]},not-a-float,1,Invalid float\n".encode(),
        f"2026-04-03T14:00:00Z,{ids[0]},150.001,2,Out of range\n".encode(),
        f"2026-04-03T10:00:00Z,{ids[1]},150.0,{sensors[2]},Upper boundary\n".encode(),
        f"2026-04-03T09:00:00Z,{ids[1]},-50.0,{sensors[3]},Lower boundary\n".encode(),
        f'2026-04-03T08:00:00Z,{ids[2]},{temp_third},{sensors[4]},"Quoted, comma note"\n'.encode(),
        b"2026-04-03T07:00:00Z,X99Y,22.0,123,Irrelevant machine\n",
    ]
    Path("/app/telemetry.csv").write_bytes(b"".join(rows))
    restart_server(pid, launch)

    expected = {
        ids[0]: [
            ("2026-04-03T11:00:00Z", temp_early, sensors[1], "Earlier record"),
            ("2026-04-03T12:00:00Z", temp_late, sensors[0], "Café résumé"),
        ],
        ids[1]: [
            ("2026-04-03T09:00:00Z", -50.0, sensors[3], "Lower boundary"),
            ("2026-04-03T10:00:00Z", 150.0, sensors[2], "Upper boundary"),
        ],
        ids[2]: [
            ("2026-04-03T08:00:00Z", temp_third, sensors[4], "Quoted, comma note"),
        ],
    }

    for machine_id, wanted in expected.items():
        data = fetch_anomalies(machine_id)
        assert isinstance(data, list)
        assert len(data) == len(wanted)
        for record, (timestamp, temperature, sensor, notes) in zip(data, wanted):
            assert_exact_keys(record)
            assert record["timestamp"] == timestamp
            assert record["machine_id"] == machine_id
            assert float(record["temperature"]) == pytest.approx(temperature)
            assert str(record["sensor_reading"]) == sensor
            assert record["status_notes"] == notes

    assert fetch_anomalies("X99Y") == []
    for old_id in ("A73B", "D90E", "O22X"):
        assert fetch_anomalies(old_id) == []
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
