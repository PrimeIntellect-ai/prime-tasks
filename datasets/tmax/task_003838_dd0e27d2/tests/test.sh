#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import shutil
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.request

FILTER_SOURCE = "/home/user/config_filter.go"
FILTER_BINARY = "/home/user/config_filter"
TEST_FILTER_BINARY = "/tmp/config_filter_bin"
SERVER_SOURCE = "/home/user/server.go"
SERVER_BINARY = "/tmp/config_server_bin"


def run_filter_bytes(data):
    fd, path = tempfile.mkstemp(prefix="configuration_", suffix=".json")
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(data)
        return subprocess.run([TEST_FILTER_BINARY, path], capture_output=True).returncode
    finally:
        os.unlink(path)


def run_filter(obj):
    return run_filter_bytes(json.dumps(obj).encode("utf-8"))


def test_config_filter_corpus_and_derived_cases():
    assert os.path.isfile(FILTER_SOURCE), f"{FILTER_SOURCE} does not exist"
    proc = subprocess.run(["go", "build", "-o", TEST_FILTER_BINARY, FILTER_SOURCE], capture_output=True, text=True)
    assert proc.returncode == 0, f"Failed to compile {FILTER_SOURCE}:\n{proc.stderr}"

    clean_dir = "/app/corpus/clean/"
    evil_dir = "/app/corpus/evil/"
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith(".json")]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith(".json")]
    assert clean_files and evil_files, "The supplied clean and evil corpora must be present"

    failed_clean = []
    for path in clean_files:
        if subprocess.run([TEST_FILTER_BINARY, path], capture_output=True).returncode != 0:
            failed_clean.append(os.path.basename(path))
    failed_evil = []
    for path in evil_files:
        if subprocess.run([TEST_FILTER_BINARY, path], capture_output=True).returncode == 0:
            failed_evil.append(os.path.basename(path))
    assert not failed_clean and not failed_evil, (
        f"clean rejected: {failed_clean}; evil accepted: {failed_evil}"
    )

    # Explicit format, presence, population-standard-deviation, and boundary cases.
    clean_cases = [
        {"services": [{"service_name": "single", "allocated_ram_mb": 100000.0, "cpu_shares": 73.25}]},
        {"services": [
            {"service_name": "population_a", "allocated_ram_mb": 40000.25, "cpu_shares": 0.0},
            {"service_name": "population_b", "allocated_ram_mb": 59999.75, "cpu_shares": 19.8},
        ]}, # population SD is 9.9; a sample-SD implementation rejects it
    ]
    evil_cases = [
        {"services": [{"service_name": "ram_over", "allocated_ram_mb": 100000.0001, "cpu_shares": 5.0}]},
        {"services": [
            {"service_name": "sd_boundary_a", "allocated_ram_mb": 1.0, "cpu_shares": 0.0},
            {"service_name": "sd_boundary_b", "allocated_ram_mb": 1.0, "cpu_shares": 20.0},
        ]}, # population SD is exactly 10 and must be rejected
        {"services": [
            {"service_name": "sd_over_a", "allocated_ram_mb": 1.0, "cpu_shares": 11.3},
            {"service_name": "sd_over_b", "allocated_ram_mb": 1.0, "cpu_shares": 35.7},
        ]},
    ]

    for case in clean_cases:
        assert run_filter(case) == 0, f"Filter rejected derived clean case: {case}"
    for case in evil_cases:
        assert run_filter(case) == 1, f"Filter did not exit 1 for derived evil case: {case}"

    malformed = [
        b"{",
        b"not json",
        b"[]",
        b"{}",
        b'{"other": []}',
        b'{"services": null}',
        b'{"services": {}}',
    ]
    for data in malformed:
        assert run_filter_bytes(data) == 1, f"Malformed or missing-services input was not rejected: {data!r}"

    # Runtime-generated paths, names, values, and cardinalities prevent fixture/path hardcoding.
    rng = random.SystemRandom()
    for _ in range(24):
        n = rng.randint(1, 8)
        base = rng.uniform(20.0, 80.0)
        services = []
        for i in range(n):
            services.append({
                "service_name": f"svc_{rng.getrandbits(64):016x}_{i}",
                "allocated_ram_mb": rng.uniform(0.1, 4500.0),
                "cpu_shares": base + rng.uniform(-4.0, 4.0),
            })
        total = sum(s["allocated_ram_mb"] for s in services)
        mean = sum(s["cpu_shares"] for s in services) / n
        pop_sd = math.sqrt(sum((s["cpu_shares"] - mean) ** 2 for s in services) / n)
        assert total <= 100000.0 and pop_sd < 10.0
        assert run_filter({"services": services}) == 0, "Runtime-generated clean input was rejected"

        excess = rng.uniform(0.01, 50000.0)
        ram_evil = {"services": [
            {"service_name": f"ram_{rng.getrandbits(64):016x}", "allocated_ram_mb": 60000.0 + excess, "cpu_shares": 40.0},
            {"service_name": f"ram_{rng.getrandbits(64):016x}", "allocated_ram_mb": 40000.0, "cpu_shares": 40.0},
        ]}
        assert run_filter(ram_evil) == 1, "Runtime-generated RAM anomaly was accepted"

        deviation = rng.uniform(10.01, 30.0)
        cpu_evil = {"services": [
            {"service_name": f"cpu_{rng.getrandbits(64):016x}", "allocated_ram_mb": rng.uniform(1.0, 1000.0), "cpu_shares": 50.0 - deviation},
            {"service_name": f"cpu_{rng.getrandbits(64):016x}", "allocated_ram_mb": rng.uniform(1.0, 1000.0), "cpu_shares": 50.0 + deviation},
        ]}
        assert run_filter(cpu_evil) == 1, "Runtime-generated CPU anomaly was accepted"

    shutil.copy2(TEST_FILTER_BINARY, FILTER_BINARY)
    os.chmod(FILTER_BINARY, 0o755)


def listener_inodes(port):
    result = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[3] == "0A" and int(fields[1].rsplit(":", 1)[1], 16) == port:
                        result.add(fields[9])
        except FileNotFoundError:
            pass
    return result


def stop_listeners(port):
    targets = listener_inodes(port)
    if not targets:
        return
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    link = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if link.startswith("socket:[") and link[8:-1] in targets:
                    try:
                        os.kill(int(entry), 15)
                    except ProcessLookupError:
                        pass
                    break
        except (FileNotFoundError, PermissionError):
            pass
    deadline = time.time() + 3
    while time.time() < deadline and listener_inodes(port):
        time.sleep(0.05)
    assert not listener_inodes(port), f"Could not stop the prior listener on port {port}"


def wait_for_port(port, process=None):
    deadline = time.time() + 8
    while time.time() < deadline:
        if process is not None and process.poll() is not None:
            raise AssertionError(f"Server exited early with status {process.returncode}")
        with socket.socket() as s:
            s.settimeout(0.2)
            if s.connect_ex(("127.0.0.1", port)) == 0:
                return
        time.sleep(0.1)
    raise AssertionError(f"Nothing is listening on 127.0.0.1:{port}")


def redis_count():
    proc = subprocess.run(["redis-cli", "GET", "valid_configs_received"], capture_output=True, text=True)
    assert proc.returncode == 0, f"redis-cli failed: {proc.stderr}"
    value = proc.stdout.strip()
    if value in ("", "(nil)"):
        return 0
    try:
        return int(value)
    except ValueError:
        raise AssertionError(f"Redis counter is not an integer: {value!r}")


def post_ingest(data):
    req = urllib.request.Request(
        "http://127.0.0.1/ingest",
        data=data,
        method="POST",
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            return response.status
    except urllib.error.HTTPError as exc:
        return exc.code


def install_probe(exit_code, marker):
    temp_path = FILTER_BINARY + ".probe"
    with open(temp_path, "w") as f:
        f.write(f"#!/bin/sh\nprintf 'invoked\\n' >> {marker}\nexit {exit_code}\n")
    os.chmod(temp_path, 0o755)
    os.replace(temp_path, FILTER_BINARY)


def test_e2e_nginx_server_filter_and_redis():
    assert os.path.isfile(SERVER_SOURCE), f"{SERVER_SOURCE} does not exist"
    assert os.path.isfile("/home/user/nginx/nginx.conf"), "Local Nginx configuration is missing"
    proc = subprocess.run(["go", "build", "-o", SERVER_BINARY, SERVER_SOURCE], capture_output=True, text=True)
    assert proc.returncode == 0, f"Failed to compile {SERVER_SOURCE}:\n{proc.stderr}"

    # Exercise the submitted server binary rather than trusting an arbitrary pre-existing listener.
    stop_listeners(8080)
    server = subprocess.Popen(
        [SERVER_BINARY], cwd="/home/user", stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    wait_for_port(8080, server)

    # The instruction requires Nginx on port 80, proxying /ingest to this backend.
    wait_for_port(80)

    rng = random.SystemRandom()
    clean = {"services": [
        {"service_name": f"web_{rng.getrandbits(64):016x}", "allocated_ram_mb": 50000.0, "cpu_shares": 20.2},
        {"service_name": f"db_{rng.getrandbits(64):016x}", "allocated_ram_mb": 50000.0, "cpu_shares": 39.8},
    ]} # total boundary and population SD 9.8
    bad_sd = {"services": [
        {"service_name": f"a_{rng.getrandbits(64):016x}", "allocated_ram_mb": 10.0, "cpu_shares": 10.0},
        {"service_name": f"b_{rng.getrandbits(64):016x}", "allocated_ram_mb": 10.0, "cpu_shares": 30.0},
    ]}
    bad_ram = {"services": [
        {"service_name": f"r_{rng.getrandbits(64):016x}", "allocated_ram_mb": 100000.0 + rng.uniform(1.0, 1000.0), "cpu_shares": 7.0}
    ]}

    count = redis_count()
    assert post_ingest(json.dumps(clean).encode()) == 200
    assert redis_count() == count + 1, "Redis counter was not incremented exactly once for a clean request"
    count += 1

    for payload in (json.dumps(bad_sd).encode(), json.dumps(bad_ram).encode(), b"{", b'{"unrelated": []}'):
        assert post_ingest(payload) == 400, f"Invalid request was not rejected: {payload!r}"
        assert redis_count() == count, "Redis counter changed for a rejected request"

    # Replace the compiled filter with controlled executables. The same randomized valid
    # body must follow the filter's changing exit status, proving the server invokes it.
    marker = f"/tmp/filter_invoked_{rng.getrandbits(64):016x}"
    probe_payload = json.dumps({"services": [{
        "service_name": f"probe_{rng.getrandbits(64):016x}",
        "allocated_ram_mb": rng.uniform(1.0, 900.0),
        "cpu_shares": rng.uniform(1.0, 90.0),
    }]}).encode()
    try:
        install_probe(0, marker)
        assert post_ingest(probe_payload) == 200, "Server did not follow a zero filter exit status"
        assert os.path.exists(marker), "Server did not invoke /home/user/config_filter"
        assert redis_count() == count + 1, "Redis counter did not increment after filter acceptance"
        count += 1

        os.unlink(marker)
        install_probe(1, marker)
        assert post_ingest(probe_payload) == 400, "Server did not follow a one filter exit status"
        assert os.path.exists(marker), "Server did not invoke /home/user/config_filter for rejection"
        assert redis_count() == count, "Redis counter changed after filter rejection"
    finally:
        temp_path = FILTER_BINARY + ".restore"
        shutil.copy2(TEST_FILTER_BINARY, temp_path)
        os.chmod(temp_path, 0o755)
        os.replace(temp_path, FILTER_BINARY)
        if os.path.exists(marker):
            os.unlink(marker)

    # Confirm normal behavior after restoring the actual submitted filter.
    assert post_ingest(json.dumps(clean).encode()) == 200
    assert redis_count() == count + 1
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
