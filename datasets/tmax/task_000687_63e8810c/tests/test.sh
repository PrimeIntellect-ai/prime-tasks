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
import json
import os
import random
import socket
import subprocess
import tempfile
import time
import uuid

import pytest
import requests

LIBDIR = "/app/tinycsv-1.0"


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, **kwargs)


def test_library_is_repaired_and_builds():
    run(["make", "-C", LIBDIR, "clean"])
    run(["make", "-C", LIBDIR, "all"])

    artifacts = [p for p in (f"{LIBDIR}/libtinycsv.a", f"{LIBDIR}/libtinycsv.so") if os.path.isfile(p)]
    assert artifacts, "The repaired tinycsv build produced neither libtinycsv.a nor libtinycsv.so"

    harness = r'''#include <stdio.h>
#include <string.h>
#include "tinycsv.h"

int main(void) {
    const char *line = "id,1,12.34,note \\u2028 tail\n";
    char **fields = NULL;
    int count = 0;
    int rc = parse_csv_line(line, &fields, &count);
    if (rc != 0 || count != 4) return 10;
    if (strcmp(fields[0], "id") != 0) return 11;
    if (strcmp(fields[2], "12.34") != 0) return 12;
    if (strcmp(fields[3], "note \\u2028 tail") != 0) return 13;
    free_csv_line(fields, count);
    return 0;
}
'''
    with tempfile.TemporaryDirectory() as td:
        src = os.path.join(td, "parser_check.c")
        exe = os.path.join(td, "parser_check")
        with open(src, "w") as f:
            f.write(harness)
        artifact = f"{LIBDIR}/libtinycsv.a" if os.path.isfile(f"{LIBDIR}/libtinycsv.a") else f"{LIBDIR}/libtinycsv.so"
        run(["gcc", "-I", LIBDIR, src, artifact, "-Wl,-rpath," + LIBDIR, "-o", exe])
        run([exe])


def listening_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    parts = line.split()
                    local = parts[1]
                    state = parts[3]
                    if state == "0A" and int(local.rsplit(":", 1)[1], 16) == port:
                        inodes.add(parts[9])
        except FileNotFoundError:
            pass

    pids = set()
    for proc in glob.glob("/proc/[0-9]*"):
        pid = os.path.basename(proc)
        for fd in glob.glob(proc + "/fd/*"):
            try:
                target = os.readlink(fd)
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                pids.add(int(pid))
    return pids


def source_can_link_tinycsv():
    sources = []
    for root in ("/home/user", "/app"):
        for path in glob.glob(root + "/**/*.c", recursive=True):
            if os.path.realpath(path) == os.path.realpath(f"{LIBDIR}/tinycsv.c"):
                continue
            try:
                text = open(path, errors="ignore").read()
            except OSError:
                continue
            if "parse_csv_line" in text:
                sources.append(path)

    artifact = f"{LIBDIR}/libtinycsv.a" if os.path.isfile(f"{LIBDIR}/libtinycsv.a") else f"{LIBDIR}/libtinycsv.so"
    with tempfile.TemporaryDirectory() as td:
        for src in sources:
            attempts = [[src]]
            siblings = [p for p in glob.glob(os.path.join(os.path.dirname(src), "*.c")) if p != src]
            if siblings:
                attempts.append([src] + siblings)
            for files in attempts:
                exe = os.path.join(td, "candidate")
                result = subprocess.run(
                    ["gcc", "-O2", "-I", LIBDIR] + files + [artifact, "-pthread", "-Wl,-rpath," + LIBDIR, "-o", exe],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                )
                if result.returncode == 0:
                    return True
    return False


def test_running_service_is_c_and_uses_tinycsv():
    deadline = time.time() + 4
    ingest_pids = set()
    metrics_pids = set()
    while time.time() < deadline:
        ingest_pids = listening_pids(8001)
        metrics_pids = listening_pids(8002)
        if ingest_pids and metrics_pids:
            break
        time.sleep(0.1)

    assert ingest_pids, "No process is listening on ingestion port 8001"
    assert metrics_pids, "No process is listening on metrics port 8002"

    for pid in ingest_pids | metrics_pids:
        with open(f"/proc/{pid}/exe", "rb") as f:
            assert f.read(4) == b"\x7fELF", f"Listener process {pid} is not a compiled ELF program"

    linked = False
    for pid in ingest_pids:
        try:
            maps = open(f"/proc/{pid}/maps", errors="ignore").read()
            if "libtinycsv" in maps:
                linked = True
        except OSError:
            pass
        for nm_args in (["nm", "-a", f"/proc/{pid}/exe"], ["nm", "-D", f"/proc/{pid}/exe"]):
            result = subprocess.run(nm_args, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
            if "parse_csv_line" in result.stdout:
                linked = True

    assert linked or source_can_link_tinycsv(), \
        "Could not verify that the C aggregation service links against and calls tinycsv"


def get_stats():
    resp = requests.get("http://127.0.0.1:8002/stats", timeout=3)
    assert resp.status_code == 200, f"Expected HTTP 200 OK, got {resp.status_code}"
    try:
        data = resp.json()
    except ValueError:
        pytest.fail(f"Failed to parse JSON from HTTP response. Raw response: {resp.text}")
    assert "unique_count" in data, f"JSON response missing 'unique_count'. Response: {data}"
    assert "total_amount" in data, f"JSON response missing 'total_amount'. Response: {data}"
    assert isinstance(data["unique_count"], int), f"unique_count is not an integer: {data}"
    assert isinstance(data["total_amount"], (int, float)), f"total_amount is not numeric: {data}"
    return data


def send_payload(payload):
    try:
        with socket.create_connection(("127.0.0.1", 8001), timeout=3) as s:
            raw = payload.encode("utf-8")
            pos = 0
            while pos < len(raw):
                step = random.randint(1, min(17, len(raw) - pos))
                s.sendall(raw[pos:pos + step])
                pos += step
                if random.random() < 0.15:
                    time.sleep(0.005)
    except Exception as e:
        pytest.fail(f"Failed to connect and send TCP payload to 127.0.0.1:8001: {e}")


def wait_for_delta(before, expected_count, expected_amount):
    deadline = time.time() + 4
    last = None
    while time.time() < deadline:
        last = get_stats()
        count_diff = last["unique_count"] - before["unique_count"]
        amount_diff = last["total_amount"] - before["total_amount"]
        if count_diff == expected_count and abs(amount_diff - expected_amount) < 0.01:
            return last
        time.sleep(0.1)
    return last


def test_original_aggregation_assertions():
    initial = get_stats()
    prefix = str(uuid.uuid4())[:8] + "_"
    slash_u = chr(92) + "u2028"
    payload = (
        f"{prefix}tx100,1700000000,10.50,clean note\n"
        f"{prefix}tx101,1700000001,20.00,malformed {slash_u} note\n"
        f"{prefix}tx100,1700000002,500.00,duplicate id should be ignored\n"
        f"{prefix}tx102,1700000003,5.25,another clean note\n"
    )
    send_payload(payload)
    final_data = wait_for_delta(initial, 3, 35.75)

    actual_count_diff = final_data["unique_count"] - initial["unique_count"]
    actual_amount_diff = final_data["total_amount"] - initial["total_amount"]
    assert actual_count_diff == 3, \
        f"Expected unique_count to increase by 3, but it increased by {actual_count_diff}"
    assert abs(actual_amount_diff - 35.75) < 0.01, \
        f"Expected total_amount to increase by 35.75, but it increased by {actual_amount_diff}"


def test_randomized_streaming_deduplication_and_aggregation():
    rng = random.SystemRandom()
    previously_seen = []

    for round_no in range(4):
        before = get_stats()
        prefix = uuid.uuid4().hex + "_"
        unique_rows = []
        duplicate_rows = []
        expected_cents = 0
        count = rng.randint(2, 7)

        for i in range(count):
            txid = f"{prefix}{i}"
            cents = rng.randint(101, 250000)
            expected_cents += cents
            amount = f"{cents // 100}.{cents % 100:02d}"
            note = f"round {round_no} row {i}"
            if i == 0 or rng.random() < 0.5:
                note += " literal " + chr(92) + f"u{rng.randint(0, 65535):04x}"
            unique_rows.append(f"{txid},{1701000000 + round_no * 100 + i},{amount},{note}\n")
            previously_seen.append(txid)
            if rng.random() < 0.75:
                fake_cents = rng.randint(300000, 900000)
                duplicate_rows.append(
                    f"{txid},{1800000000 + i},{fake_cents // 100}.{fake_cents % 100:02d},duplicate must not count\n"
                )

        rng.shuffle(duplicate_rows)
        send_payload("".join(unique_rows + duplicate_rows))
        expected_amount = expected_cents / 100.0
        final_data = wait_for_delta(before, count, expected_amount)
        assert final_data["unique_count"] - before["unique_count"] == count
        assert abs((final_data["total_amount"] - before["total_amount"]) - expected_amount) < 0.01

    before = get_stats()
    duplicate_only = "".join(
        f"{txid},1900000000,{rng.randint(500000, 999999) / 100:.2f},duplicate from earlier connection\n"
        for txid in rng.sample(previously_seen, min(5, len(previously_seen)))
    )
    send_payload(duplicate_only)
    final_data = wait_for_delta(before, 0, 0.0)
    assert final_data["unique_count"] == before["unique_count"], "Cross-connection duplicate IDs were counted again"
    assert abs(final_data["total_amount"] - before["total_amount"]) < 0.01, \
        "Cross-connection duplicate amounts changed the total"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
