#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import time
import socket
import signal
import secrets
import string
import subprocess
import urllib.request
from decimal import Decimal
import pytest

ACTIVE_PATH = "/home/user/billing_active.csv"
SOURCE_PATH = "/home/user/finops_monitor.go"
BINARY_PATH = "/home/user/finops_monitor"
SCRIPT_PATH = "/home/user/check_health.sh"
FINAL_PATH = "/home/user/final_metrics.txt"

FIXED_ACTIVE = """1,EC2,us-east-1,ACTIVE,100.50
3,S3,us-west-2,ACTIVE,20.25
4,RDS,eu-central-1,ACTIVE,200.00
6,Lambda,us-east-1,ACTIVE,5.50
7,EC2,us-west-1,ACTIVE,49.50"""

FIXED_METRICS = """cost{service="EC2"} 150.00
cost{service="Lambda"} 5.50
cost{service="RDS"} 200.00
cost{service="S3"} 20.25"""


def listener_inodes(port):
    wanted = f"{port:04X}"
    result = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    address, state, inode = fields[1], fields[3], fields[9]
                    if address.rsplit(":", 1)[1].upper() == wanted and state == "0A":
                        result.add(inode)
        except FileNotFoundError:
            pass
    return result


def listener_pids(port):
    inodes = listener_inodes(port)
    pids = set()
    if not inodes:
        return pids
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return pids


def wait_for_listener(port, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        pids = listener_pids(port)
        if pids:
            return pids
        time.sleep(0.1)
    raise AssertionError(f"No process began listening on 127.0.0.1:{port}")


def stop_listener(port):
    pids = listener_pids(port)
    for pid in pids:
        if pid > 1:
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
    deadline = time.time() + 3
    while time.time() < deadline and listener_pids(port):
        time.sleep(0.1)
    for pid in listener_pids(port):
        if pid > 1:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
    deadline = time.time() + 2
    while time.time() < deadline and listener_pids(port):
        time.sleep(0.05)
    assert not listener_pids(port), f"Could not stop the existing listener on port {port}"


def fetch(port, endpoint):
    req = urllib.request.Request(f"http://127.0.0.1:{port}{endpoint}")
    with urllib.request.urlopen(req, timeout=5) as response:
        return response.status, response.read()


def parse_metrics(body):
    return sorted(line.strip() for line in body.decode("utf-8").splitlines() if line.strip())


def random_fixture():
    suffix = "".join(secrets.choice(string.ascii_uppercase) for _ in range(10))
    services = [f"Compute_{suffix}", f"Store_{suffix}", f"Queue_{suffix}"]
    cents = [secrets.randbelow(800000) + 101 for _ in range(4)]
    rows = [
        f"901,{services[0]},r1,ACTIVE,{cents[0] // 100}.{cents[0] % 100:02d}",
        f"902,{services[1]},r2,ACTIVE,{cents[1] // 100}.{cents[1] % 100:02d}",
        f"903,{services[0]},r3,ACTIVE,{cents[2] // 100}.{cents[2] % 100:02d}",
        f"904,{services[2]},r4,ACTIVE,{cents[3] // 100}.{cents[3] % 100:02d}",
    ]
    totals = {
        services[0]: Decimal(cents[0] + cents[2]) / Decimal(100),
        services[1]: Decimal(cents[1]) / Decimal(100),
        services[2]: Decimal(cents[3]) / Decimal(100),
    }
    expected = sorted(f'cost{{service="{service}"}} {value:.2f}' for service, value in totals.items())
    return "\n".join(rows) + "\n", expected


def run_service_and_check(executable, expected, check_script=False):
    stop_listener(9090)
    proc = subprocess.Popen(
        [executable],
        cwd="/home/user",
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        pids = wait_for_listener(9090)
        assert proc.poll() is None, "The submitted monitor exited instead of serving requests"
        assert proc.pid in pids, "Port 9090 is not being served by the monitor executable that was launched"
        assert os.path.samefile(f"/proc/{proc.pid}/exe", executable), \
            "The launched artifact did not itself provide the listener on port 9090"

        status, body = fetch(9090, "/health")
        assert status == 200
        assert body == b"OK", f"Health body must be exactly b'OK', got {body!r}"

        status, body = fetch(9090, "/metrics")
        assert status == 200
        assert parse_metrics(body) == expected

        status, body = fetch(8080, "/health")
        assert status == 200 and body == b"OK"
        status, body = fetch(8080, "/metrics")
        assert status == 200
        assert parse_metrics(body) == expected, "Port 8080 did not forward the dynamic metrics from port 9090"

        if check_script:
            try:
                os.remove(FINAL_PATH)
            except FileNotFoundError:
                pass
            result = subprocess.run(["/bin/bash", SCRIPT_PATH], timeout=10, capture_output=True, text=True)
            assert result.returncode == 0, f"check_health.sh failed: {result.stderr}"
            assert os.path.exists(FINAL_PATH), "check_health.sh did not generate final_metrics.txt"
            with open(FINAL_PATH) as f:
                generated = [line.strip() for line in f if line.strip()]
            assert generated == expected, "check_health.sh did not save the sorted dynamic metrics"
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=2)
        stop_listener(9090)


def test_billing_active_csv():
    assert os.path.exists(ACTIVE_PATH), f"File {ACTIVE_PATH} is missing."
    with open(ACTIVE_PATH) as f:
        content = f.read().strip()
    assert content == FIXED_ACTIVE, f"Content of {ACTIVE_PATH} is incorrect. Expected:\n{FIXED_ACTIVE}\nGot:\n{content}"


def test_go_files_exist():
    assert os.path.exists(SOURCE_PATH), f"{SOURCE_PATH} is missing."
    assert os.path.exists(BINARY_PATH), f"{BINARY_PATH} is missing."
    assert os.path.isfile(BINARY_PATH), f"{BINARY_PATH} is not a file."
    assert os.access(BINARY_PATH, os.X_OK), f"{BINARY_PATH} is not executable."
    with open(BINARY_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY_PATH} is not a compiled ELF executable."
    info = subprocess.run(["go", "version", "-m", BINARY_PATH], capture_output=True, text=True)
    assert info.returncode == 0 and "go1" in info.stdout, f"{BINARY_PATH} is not a Go executable."


def test_check_health_script_exists():
    assert os.path.exists(SCRIPT_PATH), f"{SCRIPT_PATH} is missing."
    with open(SCRIPT_PATH) as f:
        script = f.read().lower()
    assert "curl" in script and "8080/health" in script and "8080/metrics" in script


def test_final_metrics_txt():
    assert os.path.exists(FINAL_PATH), f"File {FINAL_PATH} is missing."
    with open(FINAL_PATH) as f:
        content = f.read().strip()
    assert content == FIXED_METRICS, f"Content of {FINAL_PATH} is incorrect. Expected:\n{FIXED_METRICS}\nGot:\n{content}"


def test_port_9090_listening():
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    result = sock.connect_ex(("127.0.0.1", 9090))
    sock.close()
    assert result == 0, "No process is listening on 127.0.0.1:9090 (Go application missing or not running)."


def test_port_8080_listening_and_is_socat():
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    result = sock.connect_ex(("127.0.0.1", 8080))
    sock.close()
    assert result == 0, "No process is listening on 127.0.0.1:8080 (socat missing or not running)."
    pids = listener_pids(8080)
    assert pids, "Could not identify the port 8080 listener."
    valid = False
    for pid in pids:
        try:
            exe = os.path.realpath(f"/proc/{pid}/exe")
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                cmdline = f.read().replace(b"\0", b" ").decode("utf-8", "replace").lower()
            if os.path.basename(exe) == "socat" and "8080" in cmdline and "9090" in cmdline:
                valid = True
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    assert valid, "Port 8080 must be provided by socat forwarding to port 9090."


def test_health_endpoint():
    try:
        status, body = fetch(8080, "/health")
        assert status == 200, f"Expected status 200, got {status}"
        assert body.decode("utf-8").strip() == "OK", f"Expected body 'OK', got {body!r}"
    except Exception as e:
        pytest.fail(f"Failed to reach /health on port 8080: {e}")


def test_metrics_endpoint():
    try:
        status, body = fetch(8080, "/metrics")
        assert status == 200, f"Expected status 200, got {status}"
        expected = FIXED_METRICS.splitlines()
        assert parse_metrics(body) == expected, f"Metrics output is incorrect. Expected: {expected}, Got: {parse_metrics(body)}"
    except Exception as e:
        pytest.fail(f"Failed to reach /metrics on port 8080: {e}")


def test_dynamic_monitor_source_binary_forwarder_and_health_script():
    with open(ACTIVE_PATH, "rb") as f:
        original_active = f.read()
    compiled = "/tmp/finops_monitor_from_source"
    try:
        build = subprocess.run(
            ["go", "build", "-o", compiled, SOURCE_PATH],
            cwd="/home/user",
            timeout=60,
            capture_output=True,
            text=True,
        )
        assert build.returncode == 0, f"finops_monitor.go does not compile: {build.stderr}"

        fixture1, expected1 = random_fixture()
        with open(ACTIVE_PATH, "w") as f:
            f.write(fixture1)
        run_service_and_check(BINARY_PATH, expected1, check_script=True)

        fixture2, expected2 = random_fixture()
        with open(ACTIVE_PATH, "w") as f:
            f.write(fixture2)
        run_service_and_check(compiled, expected2, check_script=False)
    finally:
        with open(ACTIVE_PATH, "wb") as f:
            f.write(original_active)
        stop_listener(9090)
        subprocess.Popen([BINARY_PATH], cwd="/home/user", stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            wait_for_listener(9090)
            subprocess.run(["/bin/bash", SCRIPT_PATH], timeout=10, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception:
            pass
        try:
            os.remove(compiled)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
