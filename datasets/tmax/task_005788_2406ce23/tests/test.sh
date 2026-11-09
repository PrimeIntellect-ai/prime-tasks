#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import email
import email.policy
import os
import random
import re
import shutil
import subprocess
import tempfile
import time


def read_text(path):
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        return f.read()


def active_config(content):
    return "\n".join(line.split("#", 1)[0] for line in content.splitlines())


def parse_access_log(path):
    pattern = re.compile(
        r'^\S+\s+\S+\s+\S+\s+\[[^\]]+\]\s+'
        r'"([A-Z]+)\s+(\S+)\s+HTTP/\d(?:\.\d)?"\s+'
        r'(\d{3})\s+(\d+|-)\s+"[^"]*"\s+"[^"]*"\s*$'
    )
    records = []
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            if not line.strip():
                continue
            match = pattern.match(line.rstrip("\n"))
            assert match, f"Malformed or non-Nginx access-log line: {line!r}"
            method, target, status, body_bytes = match.groups()
            records.append((method, target, int(status), body_bytes))
    return records


def process_cmdline(pid):
    with open(f"/proc/{pid}/cmdline", "rb") as f:
        return f.read().replace(b"\0", b" ").decode("utf-8", "replace")


def test_nginx_config_fixed_and_services_running():
    conf_path = "/home/user/staging/nginx.conf"
    assert os.path.isfile(conf_path), f"File {conf_path} does not exist."
    content = read_text(conf_path)

    # Preserve the original assertion.
    assert "proxy_pass http://unix:/tmp/staging_app.sock;" in content, (
        "Nginx configuration does not contain the correct proxy_pass directive."
    )

    active = active_config(content)
    assert re.search(
        r"(?m)^\s*proxy_pass\s+http://unix:/tmp/staging_app\.sock;\s*$", active
    ), "The correct proxy_pass must be an active Nginx directive, not a comment."

    checked = subprocess.run(
        ["nginx", "-t", "-p", "/home/user/staging", "-c", conf_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=10,
    )
    assert checked.returncode == 0, f"Nginx configuration is invalid:\n{checked.stdout}"

    pid_path = "/home/user/staging/nginx.pid"
    assert os.path.isfile(pid_path), "Nginx PID file is missing; Nginx is not running."
    try:
        nginx_pid = int(read_text(pid_path).strip())
        nginx_exe = os.path.basename(os.readlink(f"/proc/{nginx_pid}/exe"))
        nginx_cmd = process_cmdline(nginx_pid)
    except (ValueError, OSError) as exc:
        raise AssertionError(f"Nginx PID does not identify a running process: {exc}")
    assert nginx_exe.startswith("nginx"), f"PID {nginx_pid} is not an Nginx process."
    assert "/home/user/staging" in nginx_cmd and "nginx.conf" in nginx_cmd, (
        "The running Nginx master was not started with the staging configuration."
    )

    backend_pids = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            cmd = process_cmdline(int(entry))
            exe = os.path.basename(os.readlink(f"/proc/{entry}/exe"))
        except OSError:
            continue
        if "/home/user/staging/app.py" in cmd and exe.startswith("python"):
            backend_pids.append(int(entry))
    assert backend_pids, "The Python backend app.py is not running."
    assert os.path.exists("/tmp/staging_app.sock"), "The backend Unix socket is missing."


def test_exactly_five_successful_staged_requests():
    log_path = "/home/user/staging/logs/access.log"
    assert os.path.isfile(log_path), f"Access log {log_path} does not exist."
    records = parse_access_log(log_path)
    assert len(records) == 5, f"Expected exactly 5 requests in access.log, found {len(records)}."
    for method, target, status, body_bytes in records:
        assert method == "GET" and target == "/plan", (
            f"Expected a GET request to /plan, found {method} {target}."
        )
        assert status == 200, f"Request to /plan did not return 200; found {status}."
        assert body_bytes != "-" and int(body_bytes) >= 0

    # Preserve the original parseable-request assertion.
    request_count = 0
    with open(log_path, "r") as f:
        for line in f:
            parts = line.split()
            if len(parts) > 9:
                try:
                    int(parts[9])
                    request_count += 1
                except ValueError:
                    pass
    assert request_count >= 5, f"Expected at least 5 requests in access.log, found {request_count}."


def test_logrotate_configured():
    conf_path = "/home/user/staging/logrotate.conf"
    assert os.path.isfile(conf_path), f"File {conf_path} does not exist."
    content = read_text(conf_path)

    # Preserve all original assertions.
    assert "/home/user/staging/logs/access.log" in content, (
        "logrotate.conf does not specify the correct log file."
    )
    assert re.search(r'\bdaily\b', content), "logrotate.conf is missing 'daily' directive."
    assert re.search(r'\brotate\s+5\b', content), "logrotate.conf is missing 'rotate 5' directive."
    assert re.search(r'\bcompress\b', content), "logrotate.conf is missing 'compress' directive."

    active = active_config(content)
    block = re.search(
        r"/home/user/staging/logs/access\.log\s*\{(?P<body>.*?)\}", active, re.S
    )
    assert block, "The access log must have an active logrotate configuration block."
    body = block.group("body")
    assert re.search(r"(?m)^\s*daily\s*$", body), "daily must be an active directive."
    assert re.search(r"(?m)^\s*rotate\s+5\s*$", body), "rotate 5 must be an active directive."
    assert re.search(r"(?m)^\s*compress\s*$", body), "compress must be an active directive."

    # Validate the configuration with logrotate using a safe temporary log path,
    # avoiding the deliberately permissive staging-directory permissions.
    with tempfile.TemporaryDirectory(prefix="verify-logrotate-") as td:
        test_log = os.path.join(td, "access.log")
        open(test_log, "a").close()
        test_conf = os.path.join(td, "logrotate.conf")
        transformed = content.replace("/home/user/staging/logs/access.log", test_log)
        with open(test_conf, "w") as f:
            f.write(transformed)
        result = subprocess.run(
            ["logrotate", "-d", test_conf],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=10,
        )
        assert result.returncode == 0, f"Invalid logrotate configuration:\n{result.stdout}"


def test_live_requests_and_analysis_script():
    log_path = "/home/user/staging/logs/access.log"
    before = len(parse_access_log(log_path))

    # Exercise the live Nginx/backend path. A randomized request count prevents a
    # report script with a fixed precomputed total from passing.
    live_count = random.SystemRandom().randint(1, 3)
    for _ in range(live_count):
        with tempfile.NamedTemporaryFile() as body_file:
            result = subprocess.run(
                ["curl", "-sS", "-o", body_file.name, "-w", "%{http_code}",
                 "http://127.0.0.1:8080/plan"],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=10,
            )
            assert result.returncode == 0, f"Live staging request failed: {result.stderr}"
            assert result.stdout == "200", f"Live staging request returned HTTP {result.stdout}."
            body_file.seek(0)
            assert body_file.read() == b"Capacity: 85%\r\n", "Unexpected backend response body."

    deadline = time.time() + 3
    records = []
    while time.time() < deadline:
        records = parse_access_log(log_path)
        if len(records) >= before + live_count:
            break
        time.sleep(0.1)
    assert len(records) == before + live_count, "Nginx did not log every successful live request."
    for method, target, status, _ in records[-live_count:]:
        assert (method, target, status) == ("GET", "/plan", 200)

    candidates = [
        ("/home/user/analyze.py", ["python3"]),
        ("/home/user/analyze.rb", ["ruby"]),
        ("/home/user/analyze.sh", ["bash"]),
    ]
    existing = [(path, runner) for path, runner in candidates if os.path.isfile(path)]
    assert existing, "No analysis script exists at /home/user/analyze.py, .rb, or .sh."
    script_path, runner = existing[0]
    assert shutil.which(runner[0]), f"Required interpreter {runner[0]} is unavailable."

    eml_path = "/home/user/capacity_report.eml"
    if os.path.exists(eml_path):
        os.remove(eml_path)
    run = subprocess.run(
        runner + [script_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
        cwd="/home/user",
    )
    assert run.returncode == 0, f"Analysis script failed:\n{run.stderr}"
    assert os.path.isfile(eml_path), f"Email file {eml_path} does not exist."

    # Preserve the original sum calculation and email-content assertions.
    total_bytes = 0
    request_count = 0
    with open(log_path, "r") as f:
        for line in f:
            parts = line.split()
            if len(parts) > 9:
                try:
                    total_bytes += int(parts[9])
                    request_count += 1
                except ValueError:
                    pass
    assert request_count >= 5, f"Expected at least 5 requests in access.log, found {request_count}."

    eml_content = read_text(eml_path)
    assert "To: capacity@example.com" in eml_content, "Email missing correct 'To' header."
    assert "Subject: Staging Capacity Report" in eml_content, "Email missing correct 'Subject' header."
    expected_body = f"Total bytes sent: {total_bytes}"
    assert expected_body in eml_content, (
        f"Email body does not contain the correct sum. Expected '{expected_body}'."
    )

    parsed = email.message_from_string(eml_content, policy=email.policy.default)
    assert not parsed.defects, f"Email is not valid RFC 822 syntax: {parsed.defects}"
    assert parsed.get("To") == "capacity@example.com"
    assert parsed.get("Subject") == "Staging Capacity Report"
    payload = parsed.get_body(preferencelist=("plain",)) if parsed.is_multipart() else parsed
    body = payload.get_content() if hasattr(payload, "get_content") else str(payload)
    assert expected_body in body, "The computed total must appear in the email body."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
