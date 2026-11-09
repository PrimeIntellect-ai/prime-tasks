#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import time
import uuid
import urllib.request
import pytest


def is_executable(path):
    return os.path.isfile(path) and os.access(path, os.X_OK)


def run_as_user(argv, timeout=10):
    return subprocess.run(
        ["runuser", "-u", "user", "--"] + argv,
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def stop_legacy_service():
    subprocess.run(
        ["pkill", "-f", "/home/user/legacy_app/server.py"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    deadline = time.time() + 3
    while time.time() < deadline:
        try:
            urllib.request.urlopen("http://127.0.0.1:8181/health", timeout=0.2)
        except Exception:
            return
        time.sleep(0.1)
    pytest.fail("The legacy service did not stop.")


def wait_for_health(expected="OK", timeout=5):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            response = urllib.request.urlopen("http://127.0.0.1:8181/health", timeout=0.5)
            body = response.read().decode("utf-8")
            if body == expected:
                return
            last_error = AssertionError(f"Expected {expected!r}, got {body!r}")
        except Exception as exc:
            last_error = exc
        time.sleep(0.1)
    pytest.fail(f"Health endpoint was not ready: {last_error}")


def test_automate_exp_exists_and_executable():
    path = "/home/user/automate.exp"
    assert is_executable(path), f"{path} must exist and be executable."
    with open(path, 'r') as f:
        content = f.read()
    assert 'expect' in content, f"{path} should be an expect script."
    assert 'prod' in content, f"{path} missing 'prod' answer."
    assert '8181' in content, f"{path} missing '8181' answer."
    assert 'y' in content, f"{path} missing 'y' answer."


def test_deploy_sh_exists_and_executable():
    path = "/home/user/deploy.sh"
    assert is_executable(path), f"{path} must exist and be executable."


def test_health_monitor_sh_exists_and_executable():
    path = "/home/user/health_monitor.sh"
    assert is_executable(path), f"{path} must exist and be executable."


def test_service_conf_content():
    path = "/home/user/legacy_app/service.conf"
    assert os.path.isfile(path), f"{path} does not exist. Was deploy.sh run?"
    with open(path, 'r') as f:
        content = f.read()
    assert "ENV=prod" in content, f"{path} missing ENV=prod"
    assert "PORT=8181" in content, f"{path} missing PORT=8181"
    assert "VERBOSE=y" in content, f"{path} missing VERBOSE=y"


def test_health_report_log():
    path = "/home/user/health_report.log"
    assert os.path.isfile(path), f"{path} does not exist. Was health_monitor.sh run?"
    with open(path, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]
    assert len(lines) >= 1, f"{path} is empty."
    assert "STATUS: HEALTHY" in lines[-1], f"{path} should contain STATUS: HEALTHY"


def test_deploy_sh_idempotency():
    # Since service.conf should already exist, running deploy.sh again should output the specific string
    result = subprocess.run(["/home/user/deploy.sh"], capture_output=True, text=True)
    assert result.returncode == 0, "/home/user/deploy.sh did not exit with status code 0."
    assert "Deployment already configured." in result.stdout, "deploy.sh did not output the expected message when already deployed."


def test_service_running():
    try:
        response = urllib.request.urlopen("http://127.0.0.1:8181/health", timeout=2)
        body = response.read().decode('utf-8')
        assert body == "OK", "Health endpoint did not return 'OK'."
    except Exception as e:
        pytest.fail(f"Could not connect to the service on port 8181: {e}")


def test_scripts_behave_as_required():
    automate = "/home/user/automate.exp"
    deploy = "/home/user/deploy.sh"
    monitor = "/home/user/health_monitor.sh"
    starter = "/home/user/legacy_app/start_service.sh"
    conf = "/home/user/legacy_app/service.conf"
    report = "/home/user/health_report.log"

    token = uuid.uuid4().hex
    capture = f"/tmp/automation_capture_{token}"
    finished = f"/tmp/automation_finished_{token}"
    deploy_marker = f"/tmp/deploy_called_{token}"

    # Exercise automate.exp with the requested interactive program path replaced
    # temporarily by a controlled prompt script. This proves the expect program
    # launches that artifact, sends all three answers, and waits for EOF.
    starter_stat = os.stat(starter)
    with open(starter, "rb") as f:
        original_starter = f.read()
    instrumented = f'''#!/bin/bash
printf "Enter Environment (dev/prod): "
IFS= read -r env
printf "Enter Service Port [1000-9999]: "
IFS= read -r port
printf "Enable verbose logging? (y/n): "
IFS= read -r verbose
printf '%s\\n%s\\n%s\\n' "$env" "$port" "$verbose" > {capture}
sleep 1
printf 'finished\\n' > {finished}
'''
    try:
        with open(starter, "w") as f:
            f.write(instrumented)
        os.chmod(starter, 0o755)
        started = time.monotonic()
        result = run_as_user(["/usr/bin/expect", automate], timeout=8)
        elapsed = time.monotonic() - started
        assert result.returncode == 0, f"automate.exp failed under expect: {result.stdout}{result.stderr}"
        assert os.path.isfile(capture), "automate.exp did not run start_service.sh to answer its prompts."
        with open(capture) as f:
            answers = [line.rstrip("\n") for line in f]
        assert answers == ["prod", "8181", "y"], f"automate.exp sent incorrect answers: {answers!r}"
        assert os.path.isfile(finished), "automate.exp returned before start_service.sh finished."
        assert elapsed >= 0.8, "automate.exp did not wait for the interactive script to finish."
    finally:
        with open(starter, "wb") as f:
            f.write(original_starter)
        os.chmod(starter, stat.S_IMODE(starter_stat.st_mode))
        os.chown(starter, starter_stat.st_uid, starter_stat.st_gid)
        for path in (capture, finished):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass

    # Verify the unconfigured deploy branch actually executes automate.exp.
    automate_stat = os.stat(automate)
    with open(automate, "rb") as f:
        original_automate = f.read()
    probe = f'''#!/usr/bin/expect -f
set fp [open "{deploy_marker}" w]
puts $fp "called"
close $fp
exit 0
'''
    try:
        with open(automate, "w") as f:
            f.write(probe)
        os.chmod(automate, 0o755)
        try:
            os.remove(conf)
        except FileNotFoundError:
            pass
        result = run_as_user([deploy], timeout=5)
        assert result.returncode == 0, f"deploy.sh unconfigured branch failed: {result.stdout}{result.stderr}"
        assert os.path.isfile(deploy_marker), "deploy.sh did not execute automate.exp when service.conf was absent."
    finally:
        with open(automate, "wb") as f:
            f.write(original_automate)
        os.chmod(automate, stat.S_IMODE(automate_stat.st_mode))
        os.chown(automate, automate_stat.st_uid, automate_stat.st_gid)
        try:
            os.remove(deploy_marker)
        except FileNotFoundError:
            pass

    # Run the real unconfigured deployment and validate its generated state and service.
    stop_legacy_service()
    try:
        os.remove(conf)
    except FileNotFoundError:
        pass
    result = run_as_user([deploy], timeout=10)
    assert result.returncode == 0, f"Real deployment failed: {result.stdout}{result.stderr}"
    with open(conf) as f:
        conf_lines = [line.rstrip("\n") for line in f]
    assert conf_lines == ["ENV=prod", "PORT=8181", "VERBOSE=y"], f"Unexpected configuration: {conf_lines!r}"
    wait_for_health("OK")

    # Isolate the report and execute the monitor against healthy, non-OK, and
    # connection-failure conditions, checking exactly one appended result each time.
    try:
        os.remove(report)
    except FileNotFoundError:
        pass

    result = run_as_user([monitor], timeout=6)
    assert result.returncode == 0, f"health_monitor.sh failed for a healthy service: {result.stdout}{result.stderr}"
    with open(report) as f:
        lines = [line.rstrip("\n") for line in f]
    assert lines == ["STATUS: HEALTHY"], f"Healthy check wrote unexpected log data: {lines!r}"

    stop_legacy_service()
    bad_body = "NOT_OK_" + token
    fake_code = r'''
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
body = sys.argv[1].encode()
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *args):
        pass
HTTPServer(("127.0.0.1", 8181), Handler).serve_forever()
'''
    fake = subprocess.Popen(
        ["python3", "-c", fake_code, bad_body],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        wait_for_health(bad_body)
        result = run_as_user([monitor], timeout=6)
        assert result.returncode == 0, f"health_monitor.sh failed for a non-OK response: {result.stdout}{result.stderr}"
    finally:
        fake.terminate()
        try:
            fake.wait(timeout=3)
        except subprocess.TimeoutExpired:
            fake.kill()
            fake.wait(timeout=3)
    with open(report) as f:
        lines = [line.rstrip("\n") for line in f]
    assert lines == ["STATUS: HEALTHY", "STATUS: UNHEALTHY"], f"Non-OK response was logged incorrectly: {lines!r}"

    time.sleep(0.2)
    result = run_as_user([monitor], timeout=6)
    assert result.returncode == 0, f"health_monitor.sh failed on connection failure: {result.stdout}{result.stderr}"
    with open(report) as f:
        lines = [line.rstrip("\n") for line in f]
    assert lines == ["STATUS: HEALTHY", "STATUS: UNHEALTHY", "STATUS: UNHEALTHY"], f"Connection failure was logged incorrectly: {lines!r}"

    # Leave the requested service and final report in a healthy state.
    try:
        os.remove(conf)
    except FileNotFoundError:
        pass
    result = run_as_user([deploy], timeout=10)
    assert result.returncode == 0, f"Could not restore deployed service: {result.stdout}{result.stderr}"
    wait_for_health("OK")
    result = run_as_user([monitor], timeout=6)
    assert result.returncode == 0
    with open(report) as f:
        final_lines = [line.rstrip("\n") for line in f]
    assert final_lines[-1] == "STATUS: HEALTHY"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
