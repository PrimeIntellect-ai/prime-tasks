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
import os
import resource
import secrets
import signal
import subprocess
import time

import pytest
import requests

APP = "/app"
LOG = "/app/logs/microservice.log"
TEMPLATE = "/app/templates/report.html.tmpl"
SOURCE = "/app/analyzer.c"
MONGOOSE_DIR = "/app/mongoose-7.11"
EXECUTABLE = "/tmp/analyzer_verified"
OBJECT = "/tmp/analyzer_verified.o"
PORT = 8080


def expected_report(log_path=LOG, template_path=TEMPLATE):
    errors = []
    with open(log_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split()
            if len(parts) >= 3:
                ts = int(parts[0])
                ip = parts[1]
                status = int(parts[2])
                if status >= 500:
                    errors.append((ts, ip))

    errors.sort(key=lambda x: x[0])
    max_count = 0
    peak_time = 0
    sampled_ips = []

    for i in range(len(errors)):
        end_ts = errors[i][0]
        start_ts = end_ts - 59
        window_errors = [e for e in errors if start_ts <= e[0] <= end_ts]
        count = len(window_errors)
        if count >= 10 and (count > max_count or
                            (count == max_count and end_ts > peak_time)):
            max_count = count
            peak_time = end_ts
            ips = []
            for _, ip in window_errors:
                if ip not in ips:
                    ips.append(ip)
                    if len(ips) == 3:
                        break
            sampled_ips = ips

    with open(template_path, "r") as f:
        html = f.read()
    return (html.replace("{{PEAK_TIME}}", str(peak_time))
                .replace("{{ERROR_COUNT}}", str(max_count))
                .replace("{{SAMPLED_IPS}}", ", ".join(sampled_ips)))


def listener_inodes():
    result = set()
    for path in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(path) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9:
                        local = fields[1]
                        state = fields[3]
                        if int(local.rsplit(":", 1)[1], 16) == PORT and state == "0A":
                            result.add(fields[9])
        except OSError:
            pass
    return result


def kill_port_listeners():
    inodes = listener_inodes()
    if not inodes:
        return
    me = os.getpid()
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == me:
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    try:
                        os.kill(int(entry), signal.SIGKILL)
                    except (ProcessLookupError, PermissionError):
                        pass
                    break
        except OSError:
            pass
    for _ in range(30):
        if not listener_inodes():
            return
        time.sleep(0.1)
    pytest.fail("Could not stop the previous process listening on port 8080")


def start_and_check(memory_limit=None, startup_timeout=15):
    kill_port_listeners()

    def set_limit():
        if memory_limit is not None:
            resource.setrlimit(resource.RLIMIT_AS, (memory_limit, memory_limit))

    proc = subprocess.Popen(
        [EXECUTABLE], cwd=APP, stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL, preexec_fn=set_limit
    )
    deadline = time.time() + startup_timeout
    last_error = None
    try:
        while time.time() < deadline:
            try:
                response = requests.get(
                    "http://127.0.0.1:8080/latest_incident", timeout=2
                )
                assert response.status_code == 200, (
                    f"Expected HTTP 200, got {response.status_code}"
                )
                wanted = expected_report()
                assert response.text == wanted, (
                    "Response HTML does not match expected.\n"
                    f"Expected:\n{wanted}\nActual:\n{response.text}"
                )
                return
            except requests.RequestException as exc:
                last_error = exc
                if proc.poll() is not None:
                    pytest.fail(f"Compiled analyzer exited before serving HTTP (status {proc.returncode})")
                time.sleep(0.15)
        pytest.fail(f"Failed to connect to the compiled analyzer on port 8080: {last_error}")
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
        kill_port_listeners()


def test_complete_c_analyzer():
    assert os.path.exists(LOG), f"Log file {LOG} is missing"
    assert os.path.exists(TEMPLATE), f"Template file {TEMPLATE} is missing"
    assert os.path.isfile(SOURCE), f"C source {SOURCE} is missing"
    assert os.path.isfile(os.path.join(MONGOOSE_DIR, "Makefile")), "Mongoose Makefile is missing"

    original_log = open(LOG, "rb").read()
    original_template = open(TEMPLATE, "rb").read()

    try:
        # The repaired vendored Makefile must itself successfully build mongoose.o.
        subprocess.run(["make", "clean"], cwd=MONGOOSE_DIR, check=True,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
        build = subprocess.run(["make", "all"], cwd=MONGOOSE_DIR, check=True,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               text=True, timeout=30)
        mongoose_object = os.path.join(MONGOOSE_DIR, "mongoose.o")
        assert os.path.isfile(mongoose_object), (
            f"Repaired Makefile did not produce mongoose.o. Output:\n{build.stdout}"
        )

        # Compile analyzer.c independently, prove it calls the Mongoose HTTP/event APIs,
        # and link the executable under test against the object made above.
        subprocess.run([
            "gcc", "-O2", "-I", MONGOOSE_DIR, "-c", SOURCE, "-o", OBJECT
        ], check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
           text=True, timeout=30)
        nm = subprocess.run(["nm", "-u", OBJECT], check=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True, timeout=10).stdout
        assert "mg_http_listen" in nm, "analyzer.c does not call Mongoose's HTTP listener"
        assert "mg_mgr_poll" in nm, "analyzer.c does not run the Mongoose event loop"

        subprocess.run([
            "gcc", "-O2", OBJECT, mongoose_object, "-o", EXECUTABLE,
            "-pthread", "-ldl"
        ], check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
           text=True, timeout=30)

        # Preserve the original verifier's exact response assertion, but run the
        # freshly compiled C artifact rather than trusting an existing listener.
        start_and_check()

        # Replace both inputs with an unpredictable case so a fixed response or
        # server tailored to the shipped log cannot pass.
        nonce = secrets.token_hex(12)
        dynamic_template = (
            f"<html data-check='{nonce}'><b>{{{{PEAK_TIME}}}}</b>|"
            "{{ERROR_COUNT}}|{{SAMPLED_IPS}}</html>\n"
        )
        dynamic_lines = [
            "1000 10.9.0.1 500 1",
            "1001 ignored.example 499 1",
            "1040 10.9.0.2 502 1",
        ]
        for i in range(9):
            dynamic_lines.append(f"1059 10.9.0.{3 + (i % 4)} 500 1")
        for i in range(11):
            dynamic_lines.append(f"1060 172.20.0.{1 + (i % 5)} 503 1")
        with open(TEMPLATE, "w") as f:
            f.write(dynamic_template)
        with open(LOG, "w") as f:
            f.write("\n".join(dynamic_lines) + "\n")
        start_and_check()

        # Exercise streaming on an input larger than the process's address-space
        # allowance for a whole-file buffer. A streaming implementation needs only
        # bounded state because the large prefix contains no 5xx records.
        stream_nonce = secrets.token_hex(12)
        with open(TEMPLATE, "w") as f:
            f.write(stream_nonce + ":{{PEAK_TIME}}:{{ERROR_COUNT}}:{{SAMPLED_IPS}}\n")
        with open(LOG, "wb") as f:
            line = b"1900000000 1.1.1.1 200 1\n"
            for _ in range(750000):
                f.write(line)
            for i in range(12):
                f.write(f"1900000060 203.0.113.{1 + i % 4} 500 2\n".encode())
        start_and_check(memory_limit=16 * 1024 * 1024, startup_timeout=25)
    finally:
        with open(LOG, "wb") as f:
            f.write(original_log)
        with open(TEMPLATE, "wb") as f:
            f.write(original_template)
        kill_port_listeners()

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
