#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import signal
import subprocess
import tempfile
import time
import urllib.request
import uuid

import pytest

APP_DIR = "/home/user/app"
SANITIZER_BIN = os.path.join(APP_DIR, "sanitizer")
SANITIZER_SRC = os.path.join(APP_DIR, "sanitizer.cpp")
CLEAN_CORPUS_DIR = os.path.join(APP_DIR, "corpora", "clean")
EVIL_CORPUS_DIR = os.path.join(APP_DIR, "corpora", "evil")
WORKER_DIR = os.path.join(APP_DIR, "worker")
WORKER_BIN = os.path.join(WORKER_DIR, "worker_daemon")
START_SCRIPT = os.path.join(APP_DIR, "start_services.sh")
NGINX_CONF = os.path.join(APP_DIR, "nginx", "nginx.conf")
LOG_FILE = os.path.join(WORKER_DIR, "logs", "processed.log")


def is_elf(path):
    try:
        with open(path, "rb") as f:
            return f.read(4) == b"\x7fELF"
    except OSError:
        return False


def exact_exe_pids(path):
    wanted = os.path.realpath(path)
    found = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            if os.path.realpath(f"/proc/{name}/exe") == wanted:
                found.append(int(name))
        except OSError:
            pass
    return found


def wait_until(predicate, timeout=10, interval=0.1):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            if predicate():
                return True
        except Exception:
            pass
        time.sleep(interval)
    return False


def cleanup_services():
    for pattern in ("worker_daemon", "app.py", "nginx", "redis-server"):
        subprocess.run(["pkill", "-f", pattern], capture_output=True)
    time.sleep(0.3)


def test_makefile_repair():
    """Test that the Makefile successfully builds and links the worker daemon."""
    subprocess.run(["make", "clean"], cwd=WORKER_DIR, capture_output=True)
    result = subprocess.run(["make"], cwd=WORKER_DIR, capture_output=True, text=True)
    assert result.returncode == 0, f"Make failed:\n{result.stderr}"
    assert os.path.isfile(WORKER_BIN), f"Worker binary {WORKER_BIN} was not produced."
    assert os.access(WORKER_BIN, os.X_OK), f"Worker binary {WORKER_BIN} is not executable."
    assert is_elf(WORKER_BIN), "worker_daemon is not a compiled executable."

    build_output = result.stdout + "\n" + result.stderr
    assert re.search(r"(?:^|\s)-lhiredis(?:\s|$)", build_output), \
        "The worker link command did not link hiredis."
    assert re.search(r"(?:^|\s)(?:-pthread|-lpthread)(?:\s|$)", build_output), \
        "The worker link command did not link pthread."
    ldd = subprocess.run(["ldd", WORKER_BIN], capture_output=True, text=True)
    assert ldd.returncode == 0 and "hiredis" in ldd.stdout.lower(), \
        "worker_daemon is not dynamically linked to hiredis."


def test_sanitizer_exists():
    assert os.path.isfile(SANITIZER_SRC), f"Sanitizer source {SANITIZER_SRC} is missing."
    assert os.path.isfile(SANITIZER_BIN), f"Sanitizer binary {SANITIZER_BIN} is missing."
    assert os.access(SANITIZER_BIN, os.X_OK), f"Sanitizer binary {SANITIZER_BIN} is not executable."
    assert is_elf(SANITIZER_BIN), "Sanitizer is not a compiled executable."


def test_sanitizer_clean_corpus():
    """Test that sanitizer accepts all clean files."""
    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith(('.cpp', '.cc', '.c'))]
    if not clean_files:
        clean_files = os.listdir(CLEAN_CORPUS_DIR)

    failed_files = []
    for filename in clean_files:
        filepath = os.path.join(CLEAN_CORPUS_DIR, filename)
        if not os.path.isfile(filepath):
            continue
        result = subprocess.run([SANITIZER_BIN, filepath], capture_output=True)
        if result.returncode != 0:
            failed_files.append(filename)
    assert not failed_files, f"{len(failed_files)} of {len(clean_files)} clean files modified/rejected: {', '.join(failed_files)}"


def test_sanitizer_evil_corpus():
    """Test that sanitizer rejects all evil files."""
    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith(('.cpp', '.cc', '.c'))]
    if not evil_files:
        evil_files = os.listdir(EVIL_CORPUS_DIR)

    failed_files = []
    for filename in evil_files:
        filepath = os.path.join(EVIL_CORPUS_DIR, filename)
        if not os.path.isfile(filepath):
            continue
        result = subprocess.run([SANITIZER_BIN, filepath], capture_output=True)
        if result.returncode != 1:
            failed_files.append(filename)
    assert not failed_files, f"{len(failed_files)} of {len(evil_files)} evil files bypassed: {', '.join(failed_files)}"


def test_sanitizer_generated_inputs_independent_of_path():
    """Exercise generated sources at undisclosed, misleading pathnames."""
    clean_cases = [
        """#include <vector>\nvoid matmul(const std::vector<double>& a, const std::vector<double>& b, std::vector<double>& c, int n) { for (int i=0;i<n;i++) for (int j=0;j<n;j++) for (int k=0;k<n;k++) c[i*n+j] += a[i*n+k]*b[k*n+j]; }\nint main(){return 0;}\n""",
        """#include <complex>\n#include <vector>\nvoid fft(std::vector<std::complex<double>>& x) { for (size_t i=0;i<x.size();++i) x[i] *= std::complex<double>(0.5, 0.25); }\nint main(){return 0;}\n""",
        """#include <cmath>\ndouble integrate(double a,double b){ double s=0; for(int i=0;i<1000;i++){ double x=a+(b-a)*i/1000.0; s += std::sin(x); } return s*(b-a)/1000.0; }\nint main(){return 0;}\n""",
    ]
    evil_cases = [
        "#include <unistd.h>\nint main(){ return 0; }\n",
        "#include <stdlib.h>\nint main(){ return 0; }\n",
        "int main(){ system(\"echo compromised\"); return 0; }\n",
        "int main(){ __asm__(\"mov $60, %rax\\n syscall\"); return 0; }\n",
        "int main(){ __asm__(\"int $0x80\"); return 0; }\n",
    ]

    with tempfile.TemporaryDirectory(prefix="sanitizer_cases_") as root:
        misleading_clean_dir = os.path.join(root, "evil", uuid.uuid4().hex)
        misleading_evil_dir = os.path.join(root, "clean", uuid.uuid4().hex)
        os.makedirs(misleading_clean_dir)
        os.makedirs(misleading_evil_dir)

        cases = []
        for source in clean_cases:
            path = os.path.join(misleading_clean_dir, uuid.uuid4().hex + ".cpp")
            with open(path, "w") as f:
                f.write(source)
            cases.append((path, 0))
        for source in evil_cases:
            path = os.path.join(misleading_evil_dir, uuid.uuid4().hex + ".cpp")
            with open(path, "w") as f:
                f.write(source)
            cases.append((path, 1))

        for path, expected in cases:
            result = subprocess.run([SANITIZER_BIN, path], capture_output=True, timeout=5)
            assert result.returncode == expected, \
                f"Sanitizer returned {result.returncode}, expected {expected}, for generated source {path}"


def test_end_to_end_services():
    """Verify genuine Nginx, Flask, Redis, and worker participation in the flow."""
    cleanup_services()
    os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
    if os.path.exists(LOG_FILE):
        os.remove(LOG_FILE)

    config_test = subprocess.run(
        ["nginx", "-t", "-c", NGINX_CONF], capture_output=True, text=True
    )
    assert config_test.returncode == 0, f"Invalid Nginx config: {config_test.stderr}"
    config_dump = subprocess.run(
        ["nginx", "-T", "-c", NGINX_CONF], capture_output=True, text=True
    )
    rendered = config_dump.stdout + config_dump.stderr
    assert re.search(r"listen\s+8080\s*;", rendered), "Nginx is not configured to listen on 8080."
    assert re.search(r"location\s+/api/submit", rendered), "Nginx lacks the /api/submit location."
    assert re.search(r"proxy_pass\s+http://(?:127\.0\.0\.1|localhost):5000\s*;", rendered), \
        "Nginx does not proxy /api/submit to Flask on port 5000."

    proc = subprocess.Popen([START_SCRIPT], cwd=APP_DIR, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    stopped_workers = []
    try:
        assert wait_until(lambda: subprocess.run(
            ["redis-cli", "-p", "6379", "ping"], capture_output=True, text=True
        ).stdout.strip() == "PONG", timeout=8), "Redis did not start on port 6379."
        assert wait_until(lambda: bool(exact_exe_pids(WORKER_BIN)), timeout=8), \
            "The built worker_daemon was not started."
        assert wait_until(lambda: bool(exact_exe_pids("/usr/sbin/nginx")), timeout=8), \
            "The real Nginx executable was not started."
        assert wait_until(lambda: bool(exact_exe_pids("/usr/bin/redis-server")), timeout=8), \
            "The real Redis server executable was not started."

        def flask_app_running():
            for name in os.listdir("/proc"):
                if not name.isdigit():
                    continue
                try:
                    cmd = open(f"/proc/{name}/cmdline", "rb").read().replace(b"\0", b" ").decode()
                    cwd = os.path.realpath(f"/proc/{name}/cwd")
                    if "app.py" in cmd and cwd == os.path.realpath(os.path.join(APP_DIR, "api")):
                        return True
                except OSError:
                    pass
            return False

        assert wait_until(flask_app_running, timeout=8), "The Flask app.py process was not started."

        stopped_workers = exact_exe_pids(WORKER_BIN)
        assert stopped_workers
        for pid in stopped_workers:
            os.kill(pid, signal.SIGSTOP)

        token = "submission-" + uuid.uuid4().hex
        code = f"int main(){{return 0;}} // {token}"
        req = urllib.request.Request(
            "http://localhost:8080/api/submit",
            data=json.dumps({"code": code}).encode("utf-8"),
            headers={"Content-Type": "application/json"},
        )
        try:
            with urllib.request.urlopen(req, timeout=5) as response:
                body = response.read().decode("utf-8")
                assert response.status == 200, f"API returned status {response.status}"
                parsed = json.loads(body)
                assert parsed.get("status") == "queued", f"Unexpected API response: {body}"
        except Exception as e:
            pytest.fail(f"Failed to communicate with API Gateway: {e}")

        queued = subprocess.run(
            ["redis-cli", "-p", "6379", "LRANGE", "submissions", "0", "-1"],
            capture_output=True, text=True, timeout=5
        )
        assert queued.returncode == 0 and code in queued.stdout, \
            "The request did not pass through Nginx and Flask into Redis."

        for pid in stopped_workers:
            os.kill(pid, signal.SIGCONT)
        stopped_workers = []

        def worker_logged_exact_submission():
            if not os.path.exists(LOG_FILE):
                return False
            with open(LOG_FILE, "r") as f:
                return code in f.read()

        assert wait_until(worker_logged_exact_submission, timeout=8), \
            "The real worker did not pop and log the exact Redis submission."
        assert os.path.exists(LOG_FILE), f"Worker log file {LOG_FILE} was not created. Worker did not process the job."
        with open(LOG_FILE, "r") as f:
            log_content = f.read()
        assert log_content.strip(), f"Worker log file {LOG_FILE} is empty."
    finally:
        for pid in stopped_workers:
            try:
                os.kill(pid, signal.SIGCONT)
            except OSError:
                pass
        try:
            proc.terminate()
        except OSError:
            pass
        cleanup_services()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
