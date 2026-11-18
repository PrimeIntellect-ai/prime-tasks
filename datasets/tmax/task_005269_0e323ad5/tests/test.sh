#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import re
import socket
import string
import subprocess

PROJECT = "/home/user/proxy_project"
PROXY = os.path.join(PROJECT, "proxy")


def test_build_and_run_log_exists():
    path = os.path.join(PROJECT, "build_and_run.log")
    assert os.path.isfile(path), f"Log file {path} was not created."


def test_proxy_binary_exists():
    assert os.path.isfile(PROXY), f"Proxy binary {PROXY} was not built."
    assert os.access(PROXY, os.X_OK), f"Proxy binary {PROXY} is not executable."
    with open(PROXY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "proxy is not a compiled ELF executable"

    oracle = "/app/oracle_proxy"
    assert os.path.isfile(oracle), f"Oracle binary {oracle} not found."
    with open(PROXY, "rb") as submitted, open(oracle, "rb") as reference:
        assert submitted.read() != reference.read(), "Submitted proxy is identical to the reference artifact"


def test_config_env_values():
    path = os.path.join(PROJECT, "config.env")
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read()
    assert "PROXY_PORT=8080" in content, "PROXY_PORT not set correctly in config.env"
    assert "BACKEND_URL=http://127.0.0.1:9090" in content, "BACKEND_URL not set correctly in config.env"
    assert "REDIS_HOST=127.0.0.1" in content, "REDIS_HOST not set correctly in config.env"


def test_named_logic_fixes_execute_safely():
    harness_source = r'''
#include <stdio.h>
#include <string.h>

void resolve_cache_key(int depth);
void parse_query_boundary(char *query, int len);
void read_chunked_data(void);

int main(void) {
    unsigned char guarded[66];
    memset(guarded, 'Z', sizeof(guarded));

    resolve_cache_key(0);
    parse_query_boundary((char *)guarded, 64);

    for (int i = 0; i < 64; ++i) {
        if (guarded[i] != 'a') return 10;
    }
    if (guarded[64] != 'Z' || guarded[65] != 'Z') return 11;

    memset(guarded, 'Z', sizeof(guarded));
    parse_query_boundary((char *)guarded, 0);
    if (guarded[0] != 'Z') return 12;

    read_chunked_data();
    return 0;
}
'''
    harness_c = "/tmp/proxy_logic_harness.c"
    proxy_obj = "/tmp/proxy_under_test.o"
    harness_bin = "/tmp/proxy_logic_harness"
    with open(harness_c, "w") as f:
        f.write(harness_source)

    compile_proxy = subprocess.run(
        ["gcc", "-O0", "-Dmain=proxy_submission_main", "-c",
         os.path.join(PROJECT, "proxy.c"), "-o", proxy_obj],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True
    )
    assert compile_proxy.returncode == 0, compile_proxy.stdout

    compile_harness = subprocess.run(
        ["gcc", "-O0", harness_c, proxy_obj, "-lhiredis", "-o", harness_bin],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True
    )
    assert compile_harness.returncode == 0, compile_harness.stdout

    try:
        result = subprocess.run(
            [harness_bin], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, timeout=5
        )
    except subprocess.TimeoutExpired:
        raise AssertionError("A repaired logic function failed to terminate")
    assert result.returncode == 0, (
        f"Logic harness failed with status {result.returncode}: {result.stdout}"
    )


def listening_inodes(port):
    result = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                lines = f.readlines()[1:]
        except FileNotFoundError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[3] == "0A" and fields[1].split(":")[-1].upper() == wanted:
                result.add(fields[9])
    return result


def listener_pids(port):
    inodes = listening_inodes(port)
    owners = set()
    for procdir in glob.glob("/proc/[0-9]*"):
        pid = int(procdir.rsplit("/", 1)[1])
        for fd in glob.glob(procdir + "/fd/*"):
            try:
                target = os.readlink(fd)
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                owners.add(pid)
                break
    return owners


def test_required_services_are_running():
    for port in (8080, 9090, 6379):
        with socket.create_connection(("127.0.0.1", port), timeout=2):
            pass

    with socket.create_connection(("127.0.0.1", 6379), timeout=2) as redis:
        redis.sendall(b"*1\r\n$4\r\nPING\r\n")
        answer = redis.recv(128)
    assert answer.startswith(b"+PONG"), f"Port 6379 is not a working Redis service: {answer!r}"

    owners = listener_pids(8080)
    assert owners, "No process is listening on proxy port 8080"
    matching = []
    for pid in owners:
        try:
            if os.path.samefile(f"/proc/{pid}/exe", PROXY):
                matching.append(pid)
        except OSError:
            pass
    assert matching, f"Port 8080 is not being served by the submitted proxy executable; owners={sorted(owners)}"


def request_status_line(target):
    with socket.create_connection(("127.0.0.1", 8080), timeout=2) as conn:
        conn.settimeout(2)
        request = (
            f"GET /{target} HTTP/1.1\r\n"
            "Host: 127.0.0.1\r\n"
            "Connection: close\r\n\r\n"
        ).encode("ascii")
        conn.sendall(request)
        data = b""
        while b"\n" not in data and len(data) < 4096:
            chunk = conn.recv(4096)
            if not chunk:
                break
            data += chunk
    return data.splitlines()[0] if data else b""


def test_proxy_handles_fuzzed_requests_without_refusal_hang_or_crash():
    random.seed(42)
    chars = string.ascii_letters + string.digits + "-_.~!$&'()*+,;=:@?%"
    boundary_lengths = [1, 15, 16, 31, 32, 63, 64, 127, 128, 255, 256, 511, 512, 1023, 2048]
    lengths = boundary_lengths + [random.randint(1, 2048) for _ in range(1000 - len(boundary_lengths))]

    for length in lengths:
        query = ''.join(random.choice(chars) for _ in range(length))
        status = request_status_line(query)
        assert re.fullmatch(rb"HTTP/\d\.\d [1-5]\d\d(?: .*)?", status), (
            f"Proxy did not return a valid HTTP response for request length {length}: {status[:200]!r}"
        )

    assert any(
        os.path.samefile(f"/proc/{pid}/exe", PROXY)
        for pid in listener_pids(8080)
        if os.path.exists(f"/proc/{pid}/exe")
    ), "Submitted proxy exited during fuzz testing"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
