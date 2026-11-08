#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import signal
import stat
import subprocess
import time
import urllib.error
import urllib.request
import secrets
import pytest

SECRET = "987654321-NEW-SECRET"
LOG_PATH = "/home/user/legacy-svc/app.log"
API_KEY_PATH = "/home/user/secrets/api.key"
REPORT_PATH = "/home/user/rotation_report.txt"
SOURCE_PATH = "/home/user/legacy-svc/main.go"
SERVER_PATH = "/home/user/legacy-svc/server"
BASE_URL = "http://127.0.0.1:8080/auth"


def write_key(value):
    with open(API_KEY_PATH, "w") as f:
        f.write(value)
    os.chmod(API_KEY_PATH, 0o400)


def request(path="/auth", authorization=None, debug_token=None, user_agent=None):
    req = urllib.request.Request("http://127.0.0.1:8080" + path)
    if authorization is not None:
        req.add_header("Authorization", authorization)
    if debug_token is not None:
        req.add_header("X-Debug-Token", debug_token)
    if user_agent is not None:
        req.add_header("User-Agent", user_agent)
    try:
        with urllib.request.urlopen(req, timeout=2) as response:
            return response.getcode(), response.read().decode("utf-8", "replace"), response.headers
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace"), e.headers


def listener_pids(port=8080):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if state == "0A" and int(local.rsplit(":", 1)[1], 16) == port:
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    result = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    result.add(int(name))
                    break
        except (FileNotFoundError, PermissionError):
            pass
    return result


def stop_listener():
    for sig in (signal.SIGTERM, signal.SIGKILL):
        pids = listener_pids()
        if not pids:
            return
        for pid in pids:
            if pid != os.getpid():
                try:
                    os.kill(pid, sig)
                except ProcessLookupError:
                    pass
        deadline = time.time() + 2
        while time.time() < deadline and listener_pids():
            time.sleep(0.05)
    assert not listener_pids(), "Could not stop the pre-existing service on port 8080."


def start_server(path):
    stop_listener()
    proc = subprocess.Popen([path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                            start_new_session=True)
    deadline = time.time() + 5
    while time.time() < deadline:
        if proc.poll() is not None:
            pytest.fail(f"{path} exited before serving requests (status {proc.returncode}).")
        try:
            request()
            break
        except urllib.error.URLError:
            time.sleep(0.1)
    else:
        proc.kill()
        pytest.fail(f"{path} did not start listening on port 8080.")

    assert proc.pid in listener_pids(), f"The process started from {path} does not own port 8080."
    return proc


def stop_process(proc):
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=2)
    stop_listener()


def exercise_startup_loading(binary):
    startup_secret = "VERIFY-" + secrets.token_urlsafe(24)
    replacement_secret = "REPLACED-" + secrets.token_urlsafe(24)
    marker = "MARK-" + secrets.token_urlsafe(12)
    write_key(startup_secret)
    open(LOG_PATH, "w").close()
    proc = start_server(binary)
    try:
        status, body, _ = request(authorization=startup_secret)
        assert status == 200 and "OK" in body, f"{binary} did not authenticate using the credential file."
        assert request(authorization=SECRET)[0] == 401
        assert request(authorization="WRONG-" + secrets.token_urlsafe(12))[0] == 401

        # Changing the file after launch must not change the startup credential.
        write_key(replacement_secret)
        assert request(authorization=startup_secret)[0] == 200
        assert request(authorization=replacement_secret)[0] == 401

        for path, auth in (("/auth", startup_secret), ("/auth", "invalid"), ("/missing", None)):
            status, _, headers = request(path=path, authorization=auth, debug_token=marker)
            assert "x-debug-token" not in [k.lower() for k in headers.keys()], \
                f"{binary} reflected X-Debug-Token on an HTTP {status} response."

        request(path="/probe/" + startup_secret + "/" + startup_secret,
                debug_token=startup_secret, user_agent="agent/" + startup_secret)
        time.sleep(0.3)
        assert os.path.isfile(LOG_PATH)
        with open(LOG_PATH) as f:
            log_content = f.read()
        assert startup_secret not in log_content, f"{binary} wrote its loaded credential to the log."
        assert "[REDACTED]" in log_content, f"{binary} did not redact its loaded credential."
    finally:
        stop_process(proc)


@pytest.fixture(scope="session", autouse=True)
def verify_artifacts_and_launch_submission():
    assert os.path.isfile(SOURCE_PATH), f"Source file {SOURCE_PATH} does not exist."
    assert os.path.isfile(SERVER_PATH), f"Executable {SERVER_PATH} does not exist."
    assert os.access(SERVER_PATH, os.X_OK), f"{SERVER_PATH} is not executable."

    with open(SOURCE_PATH) as f:
        source = f.read()
    assert "super-secret-123" not in source, "The original hardcoded credential remains in main.go."

    go_info = subprocess.run(["go", "version", "-m", SERVER_PATH], text=True,
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    assert go_info.returncode == 0 and "go1" in go_info.stdout, \
        f"{SERVER_PATH} is not a Go executable."

    rebuilt = "/tmp/verifier-source-server"
    build = subprocess.run(["go", "build", "-o", rebuilt, SOURCE_PATH], text=True,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    assert build.returncode == 0, "main.go does not build:\n" + build.stdout

    try:
        exercise_startup_loading(rebuilt)
        exercise_startup_loading(SERVER_PATH)
    finally:
        write_key(SECRET)

    open(LOG_PATH, "w").close()
    final_proc = start_server(SERVER_PATH)
    yield final_proc
    # Intentionally leave the submitted server running after verification.


def test_api_key_file():
    assert os.path.isfile(API_KEY_PATH), f"File {API_KEY_PATH} does not exist."

    with open(API_KEY_PATH, "r") as f:
        content = f.read().strip()
    assert content == SECRET, f"File {API_KEY_PATH} does not contain the correct secret."

    st = os.stat(API_KEY_PATH)
    perms = stat.S_IMODE(st.st_mode)
    assert perms == 0o400, f"File {API_KEY_PATH} has permissions {oct(perms)}, expected 0o400."


def test_report_file():
    assert os.path.isfile(REPORT_PATH), f"File {REPORT_PATH} does not exist."
    with open(REPORT_PATH, "r") as f:
        assert "DONE" in f.read(), f"File {REPORT_PATH} does not contain the word 'DONE'."


def test_auth_success():
    req = urllib.request.Request(BASE_URL)
    req.add_header("Authorization", SECRET)
    try:
        with urllib.request.urlopen(req) as response:
            assert response.getcode() == 200, f"Expected HTTP 200 for valid auth, got {response.getcode()}."
            body = response.read().decode("utf-8")
            assert "OK" in body, "Expected 'OK' in response body for valid auth."
    except urllib.error.HTTPError as e:
        pytest.fail(f"Expected HTTP 200 for valid auth, but got HTTP {e.code}.")
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to the server: {e.reason}. Is it running?")


def test_auth_failure():
    req = urllib.request.Request(BASE_URL)
    req.add_header("Authorization", "WRONG_SECRET_VALUE")
    try:
        urllib.request.urlopen(req)
        pytest.fail("Expected HTTP 401 for invalid auth, but request succeeded with 200 OK.")
    except urllib.error.HTTPError as e:
        assert e.code == 401, f"Expected HTTP 401 for invalid auth, got HTTP {e.code}."
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to the server: {e.reason}. Is it running?")


def test_header_removal():
    req = urllib.request.Request(BASE_URL)
    req.add_header("Authorization", SECRET)
    req.add_header("X-Debug-Token", "test-token-123")
    try:
        with urllib.request.urlopen(req) as response:
            headers = response.headers
            header_keys = [k.lower() for k in headers.keys()]
            assert "x-debug-token" not in header_keys, "X-Debug-Token header was found in the response, but it should be removed."
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect or got error: {e}")


def test_log_redaction():
    req = urllib.request.Request(BASE_URL + "/987654321-NEW-SECRET")
    req.add_header("X-Debug-Token", SECRET)
    req.add_header("User-Agent", "verification/" + SECRET)
    try:
        urllib.request.urlopen(req)
    except urllib.error.URLError:
        pass

    time.sleep(1)
    assert os.path.isfile(LOG_PATH), f"Log file {LOG_PATH} does not exist."
    with open(LOG_PATH, "r") as f:
        log_content = f.read()

    assert SECRET not in log_content, "The new secret was found unredacted in the log file."
    assert "[REDACTED]" in log_content, "The string '[REDACTED]' was not found in the log file where the secret should have been."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
