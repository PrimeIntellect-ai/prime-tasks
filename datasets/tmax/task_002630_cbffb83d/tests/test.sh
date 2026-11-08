#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pytest


def test_port_txt():
    port_file = "/home/user/port.txt"
    assert os.path.isfile(port_file), f"{port_file} does not exist."

    with open(port_file, "r") as f:
        content = f.read().strip()

    assert content == "8432", f"Expected port 8432 in {port_file}, but found '{content}'."


def test_attacker_ips():
    ips_file = "/home/user/attacker_ips.txt"
    assert os.path.isfile(ips_file), f"{ips_file} does not exist."

    with open(ips_file, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_ips = [
        "10.0.0.99",
        "172.16.0.42",
        "203.0.113.8"
    ]

    assert lines == expected_ips, f"Expected {expected_ips} in {ips_file}, but found {lines}."


def test_process_logs_go_exists():
    go_file = "/home/user/process_logs.go"
    assert os.path.isfile(go_file), f"The Go program {go_file} does not exist."
TEST_EOF

run_checks() {
    python3 -m pytest /tmp/test_final_state.py -x --tb=short || return 1

    # Confirm the recorded port is actually a listening socket owned by goserver.
    python3 - << 'PY' || return 1
import os

with open("/home/user/port.txt") as f:
    wanted = int(f.read().strip())

socket_inodes = set()
for pid in os.listdir("/proc"):
    if not pid.isdigit():
        continue
    try:
        with open(f"/proc/{pid}/comm") as f:
            if f.read().strip() != "goserver":
                continue
        for fd in os.listdir(f"/proc/{pid}/fd"):
            try:
                target = os.readlink(f"/proc/{pid}/fd/{fd}")
            except OSError:
                continue
            if target.startswith("socket:[") and target.endswith("]"):
                socket_inodes.add(target[8:-1])
    except (FileNotFoundError, PermissionError, ProcessLookupError):
        pass

assert socket_inodes, "No running goserver sockets were found"
listening_ports = set()
for table in ("/proc/net/tcp", "/proc/net/tcp6"):
    try:
        with open(table) as f:
            next(f)
            for line in f:
                fields = line.split()
                if fields[3] != "0A" or fields[9] not in socket_inodes:
                    continue
                listening_ports.add(int(fields[1].rsplit(":", 1)[1], 16))
    except FileNotFoundError:
        pass

assert wanted in listening_ports, (
    f"Port file names {wanted}, but goserver listens on {sorted(listening_ports)}"
)
PY

    test -s /home/user/process_logs.go || return 1

    tmpdir=$(mktemp -d)
    cp -a /home/user/app/traffic.log "$tmpdir/original_traffic.log" || return 1
    cp -a /home/user/attacker_ips.txt "$tmpdir/original_attacker_ips.txt" || return 1

    restore_files() {
        cp -a "$tmpdir/original_traffic.log" /home/user/app/traffic.log 2>/dev/null || true
        cp -a "$tmpdir/original_attacker_ips.txt" /home/user/attacker_ips.txt 2>/dev/null || true
        rm -rf "$tmpdir"
    }
    trap restore_files RETURN

    TMP_CASE_DIR="$tmpdir" python3 - << 'PY' || return 1
import json
import os
import random
import secrets
import urllib.parse

outdir = os.environ["TMP_CASE_DIR"]
nonce = secrets.randbelow(200) + 20
sql_ip = f"10.{nonce}.7.31"
xss_ip_1 = f"172.{(nonce + 17) % 250 + 1}.8.42"
xss_ip_2 = f"198.51.{(nonce + 37) % 250 + 1}.19"
normal_ip = f"192.0.2.{nonce % 250 + 1}"
decoy_sql_ip = f"203.0.113.{(nonce + 51) % 250 + 1}"
decoy_xss_ip = f"100.64.{(nonce + 73) % 250 + 1}.9"

sql_payload = "admin' OR 1=1 --"
xss_payload = "<script>alert('dynamic')</script>"
encoded_xss = urllib.parse.quote(xss_payload, safe="")

rows = [
    {"ip": normal_ip, "method": "GET", "path": "/search?q=ordinary", "status": 200},
    {"ip": sql_ip, "method": "POST", "path": "/login", "status": 200,
     "body": json.dumps({"username": sql_payload, "password": "x"})},
    {"ip": xss_ip_1, "method": "GET", "path": "/search?q=" + encoded_xss, "status": 200},
    {"ip": xss_ip_2, "method": "GET", "path": "/search?q=prefix" + encoded_xss, "status": 200},
    # Duplicate attack must be deduplicated.
    {"ip": xss_ip_1, "method": "GET", "path": "/search?q=" + encoded_xss, "status": 200},
    # Attack strings on the wrong endpoint must not identify these clients.
    {"ip": decoy_sql_ip, "method": "GET", "path": "/search?q=" + urllib.parse.quote(sql_payload, safe=""), "status": 200},
    {"ip": decoy_xss_ip, "method": "POST", "path": "/login", "status": 401,
     "body": json.dumps({"username": xss_payload, "password": "no"})},
]
random.SystemRandom().shuffle(rows)
with open("/home/user/app/traffic.log", "w") as f:
    for row in rows:
        f.write(json.dumps(row) + "\n")
with open(os.path.join(outdir, "expected.txt"), "w") as f:
    for ip in sorted({sql_ip, xss_ip_1, xss_ip_2}):
        f.write(ip + "\n")
PY

    rm -f /home/user/attacker_ips.txt
    mkdir -p "$tmpdir/gocache"
    (
        cd /home/user
        timeout 45s env GO111MODULE=off GOCACHE="$tmpdir/gocache" HOME="$tmpdir" \
            go run /home/user/process_logs.go >"$tmpdir/program_stdout.txt" 2>"$tmpdir/program_stderr.txt"
    ) || return 1

    test -f /home/user/attacker_ips.txt || return 1
    TMP_CASE_DIR="$tmpdir" python3 - << 'PY' || return 1
import os

base = os.environ["TMP_CASE_DIR"]
with open(os.path.join(base, "expected.txt")) as f:
    expected = [line.strip() for line in f if line.strip()]
with open("/home/user/attacker_ips.txt") as f:
    actual = [line.strip() for line in f if line.strip()]
assert actual == expected, f"Dynamic log test expected {expected}, found {actual}"
PY

    restore_files
    trap - RETURN
}

if run_checks 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
