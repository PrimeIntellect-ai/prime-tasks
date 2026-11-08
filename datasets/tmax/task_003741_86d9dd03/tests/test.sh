#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import configparser
import glob
import http.server
import os
import re
import secrets
import subprocess
import threading
import time
import urllib.error
import urllib.request

import pytest

ALERTS_DIR = "/home/user/alerts"
MONITOR_PATH = "/home/user/monitor.py"
EXPECTED_PREFIX = "To: admin@local.dev\nFrom: monitor@local.dev\nSubject: Alert - HTTP {status}\n\nThe web server returned HTTP status {status}.\n"


def cleanup_services():
    subprocess.run(["pkill", "-f", "nginx"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-f", "/home/user/app/app.py"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.2)


def clear_alerts():
    os.makedirs(ALERTS_DIR, exist_ok=True)
    for path in glob.glob(os.path.join(ALERTS_DIR, "alert_*.eml")):
        os.remove(path)


def terminate_process(proc):
    if proc is None or proc.poll() is not None:
        return
    proc.terminate()
    try:
        proc.wait(timeout=3)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=2)


def alert_files():
    return glob.glob(os.path.join(ALERTS_DIR, "alert_*.eml"))


def wait_until(predicate, timeout, message):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(0.05)
    raise AssertionError(message)


def assert_exact_alert(path, status):
    basename = os.path.basename(path)
    match = re.fullmatch(r"alert_(\d+)\.eml", basename)
    assert match, f"Alert filename has the wrong format: {basename}"
    timestamp = int(match.group(1))
    assert abs(timestamp - int(os.path.getmtime(path))) <= 3, "Alert filename does not contain its creation epoch time"
    with open(path, "r", newline="") as f:
        content = f.read()
    expected = EXPECTED_PREFIX.format(status=status)
    assert content == expected, f"Alert contents were not exact. Expected {expected!r}, got {content!r}"


def test_nginx_conf_fixed():
    nginx_conf_path = "/home/user/nginx/nginx.conf"
    assert os.path.isfile(nginx_conf_path), f"File {nginx_conf_path} is missing."

    with open(nginx_conf_path, "r") as f:
        content = f.read()

    assert "proxy_pass http://unix:/home/user/app/app.sock;" in content, "nginx.conf does not contain the corrected socket path 'app.sock'."
    assert "app_wrong.sock" not in content, "nginx.conf still contains the intentional typo 'app_wrong.sock'."


def test_supervisord_conf_valid():
    sup_conf_path = "/home/user/supervisord.conf"
    assert os.path.isfile(sup_conf_path), f"File {sup_conf_path} is missing."

    config = configparser.ConfigParser()
    try:
        config.read(sup_conf_path)
    except Exception as e:
        pytest.fail(f"Could not parse {sup_conf_path} as an ini file: {e}")

    programs = [sec for sec in config.sections() if sec.startswith("program:")]
    assert len(programs) >= 2, f"Expected at least 2 programs in supervisord.conf, found {len(programs)}."

    has_app = False
    has_nginx = False
    for prog in programs:
        cmd = config.get(prog, "command", fallback="")
        autostart = config.getboolean(prog, "autostart", fallback=False)
        autorestart = config.getboolean(prog, "autorestart", fallback=False)

        if "app.py" in cmd:
            has_app = True
            assert autostart, f"Program {prog} (app) does not have autostart=true"
            assert autorestart, f"Program {prog} (app) does not have autorestart=true"
        if "nginx" in cmd:
            has_nginx = True
            assert autostart, f"Program {prog} (nginx) does not have autostart=true"
            assert autorestart, f"Program {prog} (nginx) does not have autorestart=true"
            assert "daemon off" in cmd or "daemon off;" in cmd, f"Program {prog} (nginx) must run in foreground (e.g., daemon off;)"

    assert has_app, "supervisord.conf is missing the python app."
    assert has_nginx, "supervisord.conf is missing nginx."


def test_monitor_script_exists():
    assert os.path.isfile(MONITOR_PATH), f"File {MONITOR_PATH} is missing."


def test_supervised_deployment_and_502_alert():
    cleanup_services()
    clear_alerts()
    sup_proc = None
    nginx_proc = None
    mon_proc = None
    try:
        sup_proc = subprocess.Popen(
            ["supervisord", "-c", "/home/user/supervisord.conf", "-n"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

        def service_is_200():
            try:
                with urllib.request.urlopen("http://127.0.0.1:8080/", timeout=1) as response:
                    return response.getcode() == 200
            except Exception:
                return False

        wait_until(service_is_200, 8, "Failed to reach the supervised web application through nginx with HTTP 200")

        # Stop the supervised pair so autorestart cannot race the failure test.
        terminate_process(sup_proc)
        sup_proc = None
        cleanup_services()

        # Run nginx alone against the now-absent Unix-socket application. This
        # deterministically exercises the required 502 behavior.
        nginx_proc = subprocess.Popen(
            ["nginx", "-p", "/home/user/nginx", "-c", "/home/user/nginx/nginx.conf", "-g", "daemon off;"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

        def service_is_502():
            try:
                urllib.request.urlopen("http://127.0.0.1:8080/", timeout=1)
            except urllib.error.HTTPError as e:
                return e.code == 502
            except Exception:
                return False
            return False

        wait_until(service_is_502, 5, "Nginx did not return HTTP 502 while its upstream was down")
        mon_proc = subprocess.Popen(["python3", MONITOR_PATH], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        def find_502():
            for path in alert_files():
                try:
                    with open(path, "r") as f:
                        if "Subject: Alert - HTTP 502" in f.read():
                            return path
                except OSError:
                    pass
            return None

        path = wait_until(find_502, 3.5, "No 502 alert file was generated in /home/user/alerts/")
        assert_exact_alert(path, "502")
    finally:
        terminate_process(mon_proc)
        terminate_process(nginx_proc)
        terminate_process(sup_proc)
        cleanup_services()


def test_monitor_continuous_polling_dynamic_status_and_interval():
    cleanup_services()
    clear_alerts()
    chosen_status = secrets.choice([418, 429, 503, 504])
    request_times = []
    lock = threading.Lock()

    class SequencedHandler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            with lock:
                request_times.append(time.monotonic())
                number = len(request_times)
            status = 200 if number <= 2 else chosen_status
            self.send_response(status)
            self.send_header("Content-Length", "0")
            self.end_headers()

        def log_message(self, *args):
            pass

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 8080), SequencedHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    mon_proc = None
    try:
        mon_proc = subprocess.Popen(["python3", MONITOR_PATH], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        wait_until(lambda: len(request_times) >= 2, 4.5, "Monitor did not continuously poll the endpoint")
        assert alert_files() == [], "Monitor generated an alert for an HTTP 200 response"

        wait_until(lambda: len(request_times) >= 3, 3.5, "Monitor did not continue to a third poll")
        with lock:
            observed = list(request_times[:3])
        intervals = [observed[1] - observed[0], observed[2] - observed[1]]
        for interval in intervals:
            assert 1.5 <= interval <= 2.7, f"Monitor polling interval was {interval:.3f}s instead of approximately 2 seconds"

        failure_time = observed[2]

        def find_dynamic_alert():
            for path in alert_files():
                try:
                    with open(path, "r") as f:
                        if f"Subject: Alert - HTTP {chosen_status}" in f.read():
                            return path
                except OSError:
                    pass
            return None

        path = wait_until(find_dynamic_alert, 1.2, f"No immediate alert was generated for HTTP {chosen_status}")
        assert os.path.getmtime(path) <= time.time() + 0.2
        assert time.monotonic() - failure_time <= 1.3, "Alert was not generated immediately after the failed check"
        assert_exact_alert(path, str(chosen_status))
        assert len(alert_files()) == 1, "Unexpected extra or canned alerts were generated"
    finally:
        terminate_process(mon_proc)
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)
        cleanup_services()


def test_monitor_connection_error_is_000():
    cleanup_services()
    clear_alerts()
    mon_proc = None
    try:
        started = time.time()
        mon_proc = subprocess.Popen(["python3", MONITOR_PATH], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        def find_000_alert():
            for path in alert_files():
                try:
                    with open(path, "r") as f:
                        if "Subject: Alert - HTTP 000" in f.read():
                            return path
                except OSError:
                    pass
            return None

        path = wait_until(find_000_alert, 1.5, "Connection failure was not immediately treated as HTTP 000")
        assert os.path.getmtime(path) - started <= 1.5
        assert_exact_alert(path, "000")
        assert len(alert_files()) == 1, "Unexpected extra or canned alerts were generated"
    finally:
        terminate_process(mon_proc)
        cleanup_services()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
