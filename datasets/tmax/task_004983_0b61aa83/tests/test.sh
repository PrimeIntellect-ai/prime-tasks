#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import random
import re
import subprocess
import tempfile
import time
import urllib.error
import urllib.request

URL = "http://127.0.0.1:8080/api/query"
SRC = "/home/user/query_router"


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, **kwargs)


def request(payload):
    data = payload if isinstance(payload, bytes) else json.dumps(payload).encode()
    req = urllib.request.Request(URL, data=data,
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            return response.status, response.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode("utf-8", "replace")


def listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = open(table).read().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if int(fields[1].rsplit(":", 1)[1], 16) == port and fields[3] == "0A":
                inodes.add(fields[9])
    result = set()
    for proc in glob.glob("/proc/[0-9]*"):
        for fd in glob.glob(proc + "/fd/*"):
            try:
                target = os.readlink(fd)
            except OSError:
                continue
            match = re.fullmatch(r"socket:\[(\d+)\]", target)
            if match and match.group(1) in inodes:
                result.add(int(proc.rsplit("/", 1)[1]))
    return result


def pid_has_connection(pid, port):
    owned = set()
    for fd in glob.glob(f"/proc/{pid}/fd/*"):
        try:
            target = os.readlink(fd)
        except OSError:
            continue
        match = re.fullmatch(r"socket:\[(\d+)\]", target)
        if match:
            owned.add(match.group(1))
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = open(table).read().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if fields[9] not in owned or fields[3] != "01":
                continue
            local_port = int(fields[1].rsplit(":", 1)[1], 16)
            remote_port = int(fields[2].rsplit(":", 1)[1], 16)
            if port in (local_port, remote_port):
                return True
    return False


def compile_harness(source, harness):
    td = tempfile.mkdtemp(prefix="router-test-")
    harness_path = os.path.join(td, "harness.cpp")
    binary = os.path.join(td, "harness")
    with open(harness_path, "w") as f:
        f.write(harness)
    run(["g++", "-std=c++17", "-O2", source, harness_path, "-lpq", "-lhiredis", "-o", binary])
    return binary


def test_01_sources_compile_into_a_real_cpp_service():
    for name in ("config.hpp", "db_handler.cpp", "sanitizer.cpp", "Makefile"):
        assert os.path.isfile(os.path.join(SRC, name)), f"Missing {name}"
    run(["make", "-B"], cwd=SRC, timeout=60)
    artifact = os.path.join(SRC, "query_router")
    assert os.path.isfile(artifact) and os.access(artifact, os.X_OK), "Missing executable query_router"
    with open(artifact, "rb") as f:
        assert f.read(4) == b"\x7fELF", "query_router is not a compiled native executable"


def test_02_configuration_and_services():
    config = open(os.path.join(SRC, "config.hpp")).read()
    for value in ("appdb", "appuser", "secret", "127.0.0.1", "5432", "6379"):
        assert value in config, f"config.hpp is missing required value {value}"
    assert re.search(r"REDIS_HOST[^\n]*127\.0\.0\.1", config)
    assert re.search(r"REDIS_PORT[^\n]*6379", config)

    run(["pg_isready", "-h", "127.0.0.1", "-p", "5432"])
    assert run(["redis-cli", "-h", "127.0.0.1", "-p", "6379", "PING"]).stdout.strip() == "PONG"


def test_03_db_handler_builds_sorted_paginated_queries():
    binary = compile_harness(
        os.path.join(SRC, "db_handler.cpp"),
        r'''#include <iostream>
#include <string>
#include <cstdlib>
std::string execute_postgres_query(const std::string&, int, int);
int main(int argc, char** argv) {
    std::cout << execute_postgres_query("SELECT id, data FROM items WHERE data IS NOT NULL",
                                        std::atoi(argv[1]), std::atoi(argv[2]));
}
''')
    rng = random.SystemRandom()
    for _ in range(4):
        limit = rng.randrange(1, 40)
        offset = rng.randrange(0, 40)
        actual = run([binary, str(limit), str(offset)]).stdout.strip().rstrip(";")
        normalized = " ".join(actual.split()).lower()
        expected = ("select id, data from items where data is not null "
                    f"order by id asc limit {limit} offset {offset}")
        assert normalized == expected, f"Incorrect paginated query: {actual!r}"


def test_04_sanitizer_on_derived_adversarial_inputs():
    binary = compile_harness(
        os.path.join(SRC, "sanitizer.cpp"),
        r'''#include <iostream>
#include <string>
bool is_safe_payload(const std::string&);
int main() {
    std::string line;
    while (std::getline(std::cin, line))
        std::cout << (is_safe_payload(line) ? "1" : "0") << "\n";
}
''')
    token = "%016x" % random.SystemRandom().getrandbits(64)
    clean = [
        '{"query":"SELECT * FROM items"}',
        '{"query":"SELECT id, data FROM items WHERE data = \'A\'","limit":2,"offset":0}',
        json.dumps({"query": f"SELECT id, data FROM items WHERE data = '{token}'"}),
    ]
    evil = [
        json.dumps({"query": f"SELECT * FROM items UnIoN SELECT 1, '{token}'"}),
        json.dumps({"query": f"SELECT * FROM items WHERE data='' OR 1=1 -- {token}"}),
        json.dumps({"filter": {"$where": f"this.data == '{token}'"}}),
        json.dumps({"command": f"; cat /etc/passwd # {token}"}),
    ]
    proc = subprocess.run([binary], input="\n".join(clean + evil) + "\n", text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
    answers = proc.stdout.splitlines()
    assert answers == ["1"] * len(clean) + ["0"] * len(evil), \
        f"Sanitizer misclassified hidden inputs: {answers}"


def test_nginx_config_updated():
    config_path = "/home/user/nginx.conf"
    assert os.path.exists(config_path), f"Nginx config missing at {config_path}"
    with open(config_path, 'r') as f:
        content = f.read()

    assert "proxy_pass" in content and "8081" in content, "Nginx config does not contain proxy_pass to port 8081"
    run(["nginx", "-t", "-c", config_path])


def test_05_running_backend_is_compiled_and_reachable_through_nginx():
    status, _ = request({"query": "SELECT * FROM items"})
    assert status == 200, f"Clean request through Nginx returned {status}"

    pids = listener_pids(8081)
    assert pids, "No backend is listening on port 8081"
    native = []
    for pid in pids:
        try:
            with open(f"/proc/{pid}/exe", "rb") as f:
                if f.read(4) == b"\x7fELF":
                    native.append(pid)
        except OSError:
            pass
    assert native, "The process serving port 8081 is not a compiled native service"

    deadline = time.time() + 2
    while time.time() < deadline and not any(pid_has_connection(pid, 6379) for pid in native):
        time.sleep(0.1)
    assert any(pid_has_connection(pid, 6379) for pid in native), \
        "The running Query Router has no connection to Redis"


def test_06_live_postgres_pagination_and_hidden_http_attacks():
    rng = random.SystemRandom()
    prefix = "verify_%016x_" % rng.getrandbits(64)
    labels = [prefix + str(i) for i in range(6)]
    values = ",".join("('%s')" % value for value in labels)
    sql = "GRANT SELECT ON items TO appuser; INSERT INTO items(data) VALUES " + values + ";"
    run(["sudo", "-u", "postgres", "psql", "-d", "appdb", "-v", "ON_ERROR_STOP=1", "-c", sql])

    limit = rng.randrange(1, 4)
    offset = rng.randrange(0, 6 - limit)
    payload = {
        "query": "SELECT id, data FROM items WHERE data LIKE '%s%%'" % prefix,
        "limit": limit,
        "offset": offset,
    }
    status, body = request(payload)
    assert status == 200, f"Paginated PostgreSQL request returned {status}: {body}"
    expected = labels[offset:offset + limit]
    rejected = labels[:offset] + labels[offset + limit:]
    assert all(value in body for value in expected), f"Missing expected page values in {body!r}"
    assert all(value not in body for value in rejected), f"Response was not correctly paginated: {body!r}"

    hidden_evil = [
        {"query": "SELECT * FROM items uNiOn SELECT 1, '%s'" % prefix},
        {"query": "SELECT * FROM items WHERE data='' OR 1=1 -- %s" % prefix},
        {"filter": {"$where": "this.data == '%s'" % prefix}},
        {"command": "; /bin/sh -c 'id' # %s" % prefix},
    ]
    for payload in hidden_evil:
        status, _ = request(payload)
        assert status == 403, f"Hidden malicious payload was not blocked: {payload!r} (status {status})"


def test_adversarial_corpus():
    evil_dir = "/app/corpora/evil/"
    clean_dir = "/app/corpora/clean/"

    assert os.path.isdir(evil_dir), f"Missing evil corpus directory: {evil_dir}"
    assert os.path.isdir(clean_dir), f"Missing clean corpus directory: {clean_dir}"

    evil_files = [f for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    clean_files = [f for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]

    evil_bypassed = []
    clean_modified = []

    url = "http://127.0.0.1:8080/api/query"

    for f in evil_files:
        filepath = os.path.join(evil_dir, f)
        with open(filepath, 'rb') as fd:
            data = fd.read()

        req = urllib.request.Request(url, data=data, headers={'Content-Type': 'application/json'})
        try:
            with urllib.request.urlopen(req, timeout=3) as response:
                if response.status != 403:
                    evil_bypassed.append(f)
        except urllib.error.HTTPError as e:
            if e.code != 403:
                evil_bypassed.append(f)
        except Exception:
            evil_bypassed.append(f)

    for f in clean_files:
        filepath = os.path.join(clean_dir, f)
        with open(filepath, 'rb') as fd:
            data = fd.read()

        req = urllib.request.Request(url, data=data, headers={'Content-Type': 'application/json'})
        try:
            with urllib.request.urlopen(req, timeout=3) as response:
                if response.status != 200:
                    clean_modified.append(f)
        except urllib.error.HTTPError:
            clean_modified.append(f)
        except Exception:
            clean_modified.append(f)

    error_msgs = []
    if evil_bypassed:
        error_msgs.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        error_msgs.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")

    assert not evil_bypassed and not clean_modified, " ; ".join(error_msgs)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
