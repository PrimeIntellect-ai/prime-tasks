#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY' > /tmp/test_final_state.py
import collections
import concurrent.futures
import json
import os
import random
import secrets
import signal
import socket
import subprocess
import time
import urllib.error
import urllib.request

ROOT = "/home/user/metrics-api"
LINUX_BIN = os.path.join(ROOT, "api-linux-amd64")
WINDOWS_BIN = os.path.join(ROOT, "api-windows-amd64.exe")
LOG_FILE = os.path.join(ROOT, "linux_jobs.log")


def run(cmd, **kwargs):
    kwargs.setdefault("capture_output", True)
    kwargs.setdefault("text", True)
    kwargs.setdefault("timeout", 90)
    return subprocess.run(cmd, **kwargs)


def port_open():
    sock = socket.socket()
    sock.settimeout(0.2)
    try:
        return sock.connect_ex(("127.0.0.1", 9090)) == 0
    finally:
        sock.close()


def request(method, path, body=None):
    data = None if body is None else json.dumps(body).encode()
    headers = {"Content-Type": "application/json"} if data is not None else {}
    req = urllib.request.Request("http://127.0.0.1:9090" + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read()


def start_server(binary):
    assert not port_open(), "port 9090 is already occupied before starting the submitted server"
    proc = subprocess.Popen(
        [binary], cwd=ROOT, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
        text=True, start_new_session=True
    )
    deadline = time.time() + 8
    while time.time() < deadline:
        if proc.poll() is not None:
            stderr = proc.stderr.read()
            raise AssertionError(f"submitted server exited during startup: {stderr}")
        if port_open():
            return proc
        time.sleep(0.1)
    os.killpg(proc.pid, signal.SIGKILL)
    raise AssertionError("submitted server did not listen on port 9090")


def stop_server(proc):
    if proc.poll() is None:
        os.killpg(proc.pid, signal.SIGTERM)
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.wait(timeout=5)


def test_complete_submission():
    build_script = "/home/user/build_cross.sh"
    test_script = "/home/user/test_api.sh"
    linux_logger = os.path.join(ROOT, "logger_linux.go")
    windows_logger = os.path.join(ROOT, "logger_windows.go")

    # Preserve the original existence and executable checks.
    assert os.path.exists(build_script), f"{build_script} does not exist."
    assert os.access(build_script, os.X_OK), f"{build_script} is not executable."
    assert os.path.exists(test_script), f"{test_script} does not exist."
    assert os.access(test_script, os.X_OK), f"{test_script} is not executable."
    assert os.path.exists(linux_logger), f"{linux_logger} does not exist."
    assert os.path.exists(windows_logger), f"{windows_logger} does not exist."

    go_mod = os.path.join(ROOT, "go.mod")
    assert os.path.exists(go_mod), "go.mod does not exist"
    module_lines = [line.strip() for line in open(go_mod) if line.strip().startswith("module ")]
    assert module_lines == ["module metrics-api"], f"Go module must be named metrics-api, got {module_lines}"

    with open(linux_logger) as f:
        linux_content = f.read()
    with open(windows_logger) as f:
        windows_content = f.read()
    assert "//go:build linux" in linux_content, f"//go:build linux tag missing in {linux_logger}."
    assert "//go:build windows" in windows_content, f"//go:build windows tag missing in {windows_logger}."

    # Confirm the application only imports the main module plus standard-library packages.
    deps = run(["go", "list", "-deps", "-f", "{{if .Module}}{{.Module.Path}}{{end}}", "."], cwd=ROOT)
    assert deps.returncode == 0, f"go list failed:\n{deps.stderr}\n{deps.stdout}"
    modules = {line.strip() for line in deps.stdout.splitlines() if line.strip()}
    assert modules == {"metrics-api"}, f"application uses non-standard modules: {sorted(modules)}"
    net_http = run(["go", "list", "-deps", "-f", "{{.ImportPath}}", "."], cwd=ROOT)
    assert net_http.returncode == 0 and "net/http" in net_http.stdout.splitlines(), "application does not use net/http"

    # Run the submitted build script, retaining the original assertion.
    built = run([build_script], cwd="/home/user")
    assert built.returncode == 0, f"build_cross.sh failed with output:\n{built.stderr}\n{built.stdout}"
    assert os.path.exists(LINUX_BIN), f"{LINUX_BIN} was not created."
    assert os.path.exists(WINDOWS_BIN), f"{WINDOWS_BIN} was not created."

    linux_file = run(["file", LINUX_BIN]).stdout
    windows_file = run(["file", WINDOWS_BIN]).stdout
    assert "ELF 64-bit" in linux_file, f"{LINUX_BIN} is not an ELF 64-bit executable."
    assert "PE32+" in windows_file and "Windows" in windows_file, f"{WINDOWS_BIN} is not a Windows PE32+ executable."

    # Ensure the Windows artifact contains the required platform-specific implementation.
    windows_bytes = open(WINDOWS_BIN, "rb").read()
    assert b"[WINDOWS] Platform: " in windows_bytes, "Windows binary lacks the required Windows log format"
    assert b"/home/user/metrics-api/windows_jobs.log" in windows_bytes, "Windows binary lacks the required log path"

    # Check that the required test script describes the specified real requests and lifecycle.
    test_text = open(test_script).read()
    for required in [
        "api-linux-amd64", "/job/ios/101", "/job/android/201", "/job/ios/102",
        "/summary/ios", "ios_summary.json", '"duration": 120',
        '"duration": 300', '"duration": 45'
    ]:
        assert required in test_text, f"test_api.sh is missing required operation/text: {required}"
    assert "&" in test_text and "kill" in test_text, "test_api.sh must background and kill the API server"

    # Preserve the original execution and fixed-output assertions, starting from clean artifacts.
    for path in [LOG_FILE, "/home/user/ios_summary.json"]:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    assert not port_open(), "port 9090 is occupied before test_api.sh"
    script_proc = subprocess.Popen(
        [test_script], cwd="/home/user", stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, start_new_session=True
    )
    try:
        stdout, stderr = script_proc.communicate(timeout=30)
    except subprocess.TimeoutExpired:
        os.killpg(script_proc.pid, signal.SIGKILL)
        stdout, stderr = script_proc.communicate()
        raise AssertionError(f"test_api.sh timed out:\n{stderr}\n{stdout}")
    assert script_proc.returncode == 0, f"test_api.sh failed with output:\n{stderr}\n{stdout}"

    deadline = time.time() + 2
    while port_open() and time.time() < deadline:
        time.sleep(0.1)
    assert not port_open(), "test_api.sh did not stop the API server"

    assert os.path.exists(LOG_FILE), f"{LOG_FILE} does not exist."
    log_content = open(LOG_FILE).read()
    for line in [
        "[LINUX] Platform: ios, Job: 101",
        "[LINUX] Platform: android, Job: 201",
        "[LINUX] Platform: ios, Job: 102"
    ]:
        assert line in log_content, f"Expected log line '{line}' not found in {LOG_FILE}."

    summary_file = "/home/user/ios_summary.json"
    assert os.path.exists(summary_file), f"{summary_file} does not exist."
    try:
        saved_summary = json.load(open(summary_file))
    except json.JSONDecodeError as exc:
        raise AssertionError(f"{summary_file} does not contain valid JSON: {exc}")
    assert saved_summary.get("job_count") == 2, f"Expected job_count to be 2, got {saved_summary.get('job_count')}."
    assert saved_summary.get("total_duration") == 165, f"Expected total_duration to be 165, got {saved_summary.get('total_duration')}."

    # Independently execute and exercise the submitted Linux artifact with unpredictable data.
    try:
        os.remove(LOG_FILE)
    except FileNotFoundError:
        pass
    proc = start_server(LINUX_BIN)
    try:
        platform = "audit_" + secrets.token_hex(6)
        other_platform = "other_" + secrets.token_hex(6)

        status, raw = request("GET", f"/summary/{platform}")
        assert status == 200, f"initial summary returned HTTP {status}: {raw!r}"
        assert json.loads(raw) == {"job_count": 0, "total_duration": 0}

        count = 120
        durations = [random.randint(1, 5000) for _ in range(count)]
        job_ids = [secrets.token_hex(8) for _ in range(count)]

        def post_one(item):
            job_id, duration = item
            return job_id, duration, request(
                "POST", f"/job/{platform}/{job_id}",
                {"status": "passed" if duration % 2 else "failed", "duration": duration}
            )

        with concurrent.futures.ThreadPoolExecutor(max_workers=24) as pool:
            results = list(pool.map(post_one, zip(job_ids, durations)))
        for job_id, duration, (status, raw) in results:
            assert status == 200, f"POST for {job_id}/{duration} returned HTTP {status}: {raw!r}"

        other_id = secrets.token_hex(8)
        other_duration = random.randint(10, 9000)
        status, raw = request("POST", f"/job/{other_platform}/{other_id}", {"status": "passed", "duration": other_duration})
        assert status == 200, f"other-platform POST returned HTTP {status}: {raw!r}"

        status, raw = request("GET", f"/summary/{platform}")
        assert status == 200, f"summary returned HTTP {status}: {raw!r}"
        assert json.loads(raw) == {"job_count": count, "total_duration": sum(durations)}, raw

        status, raw = request("GET", f"/summary/{other_platform}")
        assert status == 200, f"other summary returned HTTP {status}: {raw!r}"
        assert json.loads(raw) == {"job_count": 1, "total_duration": other_duration}, raw
    finally:
        stop_server(proc)

    assert os.path.exists(LOG_FILE), "successful POST requests did not create linux_jobs.log"
    actual_lines = open(LOG_FILE).read().splitlines()
    expected_lines = [f"[LINUX] Platform: {platform}, Job: {job_id}" for job_id in job_ids]
    expected_lines.append(f"[LINUX] Platform: {other_platform}, Job: {other_id}")
    assert collections.Counter(actual_lines) == collections.Counter(expected_lines), "Linux logger output was missing, duplicated, or not in the exact required format"
PY

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
