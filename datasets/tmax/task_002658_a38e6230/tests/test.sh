#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import secrets
import signal
import stat
import subprocess
import tempfile
import time
import urllib.error
import urllib.request

SANITIZER = "/home/user/app/filter/sanitizer"
SOURCE = "/home/user/app/filter/sanitizer.cpp"
MALICIOUS = ["../", "<script>", "DROP TABLE", "$(whoami)", "; rm -rf"]


def run_sanitizer(binary, payload):
    directory = tempfile.mkdtemp(prefix="payload_" + secrets.token_hex(6) + "_")
    path = os.path.join(directory, secrets.token_hex(8) + ".txt")
    with open(path, "w", encoding="utf-8") as f:
        f.write(payload)
    try:
        return subprocess.run([binary, os.path.abspath(path)], capture_output=True, timeout=3).returncode
    finally:
        try:
            os.unlink(path)
            os.rmdir(directory)
        except OSError:
            pass


def exercise_sanitizer(binary):
    salt = secrets.token_hex(16)
    malicious_cases = []
    for token in MALICIOUS:
        malicious_cases.extend([
            salt + token + secrets.token_hex(9),
            "first line\n" + secrets.token_hex(7) + token + "\nlast line",
            token,
        ])

    clean_cases = [
        "",
        "ordinary payload " + salt,
        ".. / <Script> DROP  TABLE $ (whoami) ;rm -rf " + salt,
        "prefix" + secrets.token_hex(24) + "suffix",
        "multiple\nclean\nlines\n" + salt,
    ]

    for payload in malicious_cases:
        assert run_sanitizer(binary, payload) == 1, repr(payload)
    for payload in clean_cases:
        assert run_sanitizer(binary, payload) == 0, repr(payload)


def test_sanitizer_artifacts_and_generated_inputs(tmp_path):
    assert os.path.isfile(SANITIZER), f"Sanitizer binary not found at {SANITIZER}"
    assert not os.path.islink(SANITIZER), "Sanitizer must be a real compiled artifact"
    assert stat.S_ISREG(os.stat(SANITIZER).st_mode), "Sanitizer is not a regular file"
    assert os.access(SANITIZER, os.X_OK), "Sanitizer is not executable"
    with open(SANITIZER, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Sanitizer is not a compiled ELF binary"

    assert os.path.isfile(SOURCE), f"C++ source not found at {SOURCE}"
    assert not os.path.islink(SOURCE), "sanitizer.cpp must be a real source file"
    rebuilt = tmp_path / ("rebuilt_" + secrets.token_hex(8))
    result = subprocess.run(
        ["g++", SOURCE, "-o", str(rebuilt)], capture_output=True, text=True, timeout=30
    )
    assert result.returncode == 0, f"sanitizer.cpp does not compile with g++: {result.stderr}"

    exercise_sanitizer(SANITIZER)
    exercise_sanitizer(str(rebuilt))


def test_sanitizer_evil_corpus_by_actual_contents():
    evil_files = glob.glob("/home/user/corpora/evil/*")
    assert len(evil_files) > 0, "No files found in evil corpus"
    failures = []
    for path in evil_files:
        with open(path, "r", encoding="utf-8") as f:
            content = f.read()
        expected = 1 if any(token in content for token in MALICIOUS) else 0
        result = subprocess.run([SANITIZER, os.path.abspath(path)], capture_output=True, timeout=3)
        if result.returncode != expected:
            failures.append(f"{os.path.basename(path)} expected {expected}, got {result.returncode}")
    assert not failures, "; ".join(failures)


def test_sanitizer_clean_corpus():
    clean_files = glob.glob("/home/user/corpora/clean/*")
    assert len(clean_files) > 0, "No files found in clean corpus"
    modified_files = []
    for path in clean_files:
        result = subprocess.run([SANITIZER, os.path.abspath(path)], capture_output=True, timeout=3)
        if result.returncode != 0:
            modified_files.append(os.path.basename(path))
    assert not modified_files, f"Clean files rejected: {', '.join(modified_files)}"


def test_nginx_config_updated():
    path = "/home/user/app/nginx/nginx.conf"
    assert os.path.isfile(path), "nginx.conf not found"
    with open(path, "r") as f:
        content = f.read()
    assert "proxy_pass http://127.0.0.1:9090;" in content, \
        "nginx.conf does not route to 127.0.0.1:9090"


def test_backend_config_updated():
    path = "/home/user/app/backend/config.json"
    assert os.path.isfile(path), "config.json not found"
    with open(path, "r") as f:
        config = json.load(f)
    assert config.get("redis_host") == "127.0.0.1", \
        "Backend config.json does not point to redis host 127.0.0.1"
    assert config.get("redis_port") == 6379, \
        "Backend config.json does not point to redis port 6379"


def submit(payload, expected_status, timeout=3):
    req = urllib.request.Request(
        "http://127.0.0.1:8080/api/submit",
        data=payload.encode("utf-8"),
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            status = response.status
    except urllib.error.HTTPError as e:
        status = e.code
    assert status == expected_status, f"Expected HTTP {expected_status}, got {status}"


def wait_for_stack(payload):
    deadline = time.time() + 12
    last_error = None
    while time.time() < deadline:
        try:
            submit(payload, 200)
            result = subprocess.run(
                ["redis-cli", "--raw", "GET", "last_payload"],
                capture_output=True, text=True, timeout=3
            )
            if result.returncode == 0 and result.stdout.rstrip("\n") == payload:
                return
        except Exception as e:
            last_error = e
        time.sleep(0.4)
    raise AssertionError(f"Services did not become interconnected: {last_error}")


def test_end_to_end_flow_and_rejection():
    clean = "clean-" + secrets.token_hex(16)
    wait_for_stack(clean)

    marker = "marker-" + secrets.token_hex(16)
    submit(marker, 200)
    malicious = secrets.token_hex(8) + MALICIOUS[secrets.randbelow(len(MALICIOUS))] + secrets.token_hex(8)
    submit(malicious, 403)
    result = subprocess.run(
        ["redis-cli", "--raw", "GET", "last_payload"],
        capture_output=True, text=True, check=True, timeout=3
    )
    assert result.stdout.rstrip("\n") == marker, "Rejected payload was cached in Redis"


def process_pids(service):
    found = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/stat", "r") as f:
                fields = f.read().split()
            if len(fields) > 2 and fields[2] == "Z":
                continue
            with open(f"/proc/{entry}/comm", "r") as f:
                comm = f.read().strip()
            with open(f"/proc/{entry}/cmdline", "rb") as f:
                cmdline = f.read().replace(b"\0", b" ").decode("utf-8", "ignore")
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            continue

        matches = ((service == "nginx" and comm == "nginx") or
                   (service == "redis-server" and comm.startswith("redis-server")) or
                   (service == "backend.py" and "backend.py" in cmdline))
        if matches:
            found.append(int(entry))
    return found


def kill_service(service):
    for pid in process_pids(service):
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 4
    while time.time() < deadline and process_pids(service):
        time.sleep(0.1)
    for pid in process_pids(service):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and process_pids(service):
        time.sleep(0.1)
    assert not process_pids(service), f"Could not stop {service} for health-monitor test"


def test_health_monitor_script_recovers_each_service():
    monitor = "/home/user/app/health_monitor.sh"
    assert os.path.isfile(monitor), f"{monitor} not found"
    assert os.access(monitor, os.X_OK), f"{monitor} is not executable"

    services = ["nginx", "redis-server", "backend.py"]
    for service in services:
        kill_service(service)
        subprocess.run([monitor], capture_output=True, timeout=20)
        payload = "health-" + service.replace(".", "-") + "-" + secrets.token_hex(10)
        wait_for_stack(payload)
        missing = [name for name in services if not process_pids(name)]
        assert not missing, f"Health monitor failed to restore: {', '.join(missing)}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
