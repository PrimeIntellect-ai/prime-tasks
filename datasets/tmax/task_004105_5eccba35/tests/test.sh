#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import re
import subprocess
import tempfile
import time
import urllib.request
import urllib.error
import concurrent.futures
import pytest

APP_DIR = "/home/user/app"
MONITOR_SH = os.path.join(APP_DIR, "monitor.sh")
BACKEND_ARM = os.path.join(APP_DIR, "backend_arm")

def test_monitor_script_exists():
    assert os.path.isfile(MONITOR_SH), f"Monitor script {MONITOR_SH} does not exist."
    assert os.access(MONITOR_SH, os.X_OK) or "bash" in open(MONITOR_SH).read() or "sh" in open(MONITOR_SH).read(), \
        f"Monitor script {MONITOR_SH} should be executable or contain shell commands."

def test_backend_compiled():
    assert os.path.isfile(BACKEND_ARM), f"Compiled backend {BACKEND_ARM} does not exist."
    # Check if it's an ARM binary
    output = subprocess.check_output(["file", BACKEND_ARM]).decode()
    assert "ARM" in output or "aarch64" in output, f"{BACKEND_ARM} is not compiled for ARM/aarch64."

def test_services_running():
    # Check if Nginx is running
    pgrep_nginx = subprocess.run(["pgrep", "-f", "nginx"], capture_output=True)
    assert pgrep_nginx.returncode == 0, "Nginx is not running."

    # Check if QEMU backend is running
    pgrep_qemu = subprocess.run(["pgrep", "-f", "qemu-aarch64-static.*backend_arm"], capture_output=True)
    assert pgrep_qemu.returncode == 0, "Backend is not running via qemu-aarch64-static."

def test_basic_request():
    max_retries = 5
    for _ in range(max_retries):
        try:
            req = urllib.request.Request("http://127.0.0.1:8080/")
            with urllib.request.urlopen(req, timeout=2) as response:
                assert response.status == 200, f"Expected HTTP 200, got {response.status}"
                body = response.read().decode()
                assert "OK" in body, "Response body did not contain 'OK'"
                return
        except urllib.error.URLError as e:
            time.sleep(1)
    pytest.fail("Failed to connect to Nginx on 127.0.0.1:8080 or received bad response.")

def test_throughput_metric():
    # Attempt to use wrk as specified in the verifier details
    try:
        cmd = ["wrk", "-c", "20", "-d", "5s", "http://127.0.0.1:8080/"]
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        match = re.search(r"Requests/sec:\s+([\d\.]+)", result.stdout)
        if match:
            req_per_sec = float(match.group(1))
            assert req_per_sec >= 500.0, f"Throughput too low: {req_per_sec} req/sec (Threshold: 500.0). Did you remove the sleep(1) delay?"
            return
    except (FileNotFoundError, subprocess.CalledProcessError):
        pass # Fallback to python-based load test if wrk is missing or fails

    # Fallback Python load test
    def fetch():
        try:
            with urllib.request.urlopen("http://127.0.0.1:8080/", timeout=2) as response:
                return response.status == 200
        except Exception:
            return False

    start_time = time.time()
    success_count = 0
    total_requests = 200

    with concurrent.futures.ThreadPoolExecutor(max_workers=20) as executor:
        futures = [executor.submit(fetch) for _ in range(total_requests)]
        for f in concurrent.futures.as_completed(futures):
            if f.result():
                success_count += 1

    duration = time.time() - start_time
    req_per_sec = success_count / duration

    # The python fallback is much slower than wrk, so we adjust the threshold for the fallback
    # If sleep(1) is present, throughput will be ~1-20 req/sec. Without it, it should easily exceed 100.
    assert req_per_sec >= 100.0, f"Throughput too low: {req_per_sec:.2f} req/sec (Fallback Threshold: 100.0). Did you remove the sleep(1) delay?"

def qemu_pids_for(binary_path):
    matches = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        try:
            with open(f"/proc/{entry}/cmdline", "rb") as f:
                argv = [x.decode(errors="replace") for x in f.read().split(b"\0") if x]
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        if argv and "qemu-aarch64-static" in os.path.basename(argv[0]) and binary_path in argv[1:]:
            matches.append(int(entry))
    return matches

def stop_pids(pids):
    for pid in pids:
        try:
            os.kill(pid, 15)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline:
        remaining = [pid for pid in pids if os.path.exists(f"/proc/{pid}")]
        if not remaining:
            return
        time.sleep(0.05)
    for pid in pids:
        try:
            os.kill(pid, 9)
        except ProcessLookupError:
            pass

def test_monitor_recovers_failed_backend():
    # Run a harmless ARM process named backend_arm as a stale backend. A correct
    # monitor must kill it when the real backend outage causes Nginx to return 502.
    with tempfile.TemporaryDirectory(prefix="monitor_probe_") as probe_dir:
        stale_source = os.path.join(probe_dir, "stale.c")
        stale_binary = os.path.join(probe_dir, "backend_arm")
        with open(stale_source, "w") as f:
            f.write("#include <unistd.h>\nint main(void) { for (;;) sleep(60); }\n")
        subprocess.run(
            ["aarch64-linux-gnu-gcc", "-static", "-o", stale_binary, stale_source],
            check=True,
            capture_output=True,
        )
        stale = subprocess.Popen(
            ["qemu-aarch64-static", stale_binary],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        monitor = None
        recovered = False
        stale_killed = False
        saw_502 = False
        try:
            time.sleep(0.2)
            assert stale.poll() is None, "Could not start the stale ARM backend process used to test monitor cleanup."

            old_backend_pids = qemu_pids_for(BACKEND_ARM)
            assert old_backend_pids, "No running submitted backend was found before the monitor recovery test."
            stop_pids(old_backend_pids)

            deadline = time.time() + 5
            while time.time() < deadline:
                try:
                    urllib.request.urlopen("http://127.0.0.1:8080/", timeout=1)
                except urllib.error.HTTPError as exc:
                    if exc.code == 502:
                        saw_502 = True
                        break
                except urllib.error.URLError:
                    pass
                time.sleep(0.1)
            assert saw_502, "The induced backend outage did not produce the expected Nginx 502 response."

            monitor = subprocess.Popen(
                ["/bin/bash", MONITOR_SH],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )

            deadline = time.time() + 12
            while time.time() < deadline:
                stale_killed = stale.poll() is not None
                restarted_pids = qemu_pids_for(BACKEND_ARM)
                healthy = False
                if restarted_pids:
                    try:
                        with urllib.request.urlopen("http://127.0.0.1:8080/", timeout=1) as response:
                            healthy = response.status == 200 and "OK" in response.read().decode()
                    except Exception:
                        healthy = False
                if stale_killed and restarted_pids and healthy:
                    recovered = True
                    break
                time.sleep(0.2)
        finally:
            if monitor is not None and monitor.poll() is None:
                monitor.terminate()
                try:
                    monitor.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    monitor.kill()
            if stale.poll() is None:
                stale.kill()
                stale.wait(timeout=2)

        assert stale_killed, "monitor.sh did not kill an existing backend_arm process after the 502."
        assert recovered, "monitor.sh did not restart the submitted backend through qemu-aarch64-static and restore HTTP 200 service."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
