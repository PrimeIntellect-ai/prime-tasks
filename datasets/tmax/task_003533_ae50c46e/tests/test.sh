#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import json
import locale
import os
import pwd
import re
import shutil
import subprocess
import time

import pytest

CONF_PATH = "/home/user/nginx/nginx.conf"
JOB_PATH = "/home/user/scripts/run_job.sh"
REPORT_PATH = "/home/user/app_data/report.json"
RESPONSE_PATH = "/home/user/success_response.txt"


def curl(url):
    return subprocess.run(
        ["curl", "-sS", "--fail", "--max-time", "5", url],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    ).stdout


def matching_processes(required_parts):
    matches = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            with open(f"/proc/{name}/cmdline", "rb") as f:
                cmdline = f.read().replace(b"\0", b" ").decode("utf-8", "replace")
            if all(part in cmdline for part in required_parts):
                with open(f"/proc/{name}/status", "r") as f:
                    status = f.read()
                uid_line = next(line for line in status.splitlines() if line.startswith("Uid:"))
                effective_uid = int(uid_line.split()[2])
                matches.append((int(name), effective_uid, cmdline))
        except (FileNotFoundError, PermissionError, ProcessLookupError, StopIteration):
            pass
    return matches


def test_nginx_config_fixed():
    assert os.path.isfile(CONF_PATH), f"File {CONF_PATH} is missing."
    with open(CONF_PATH, "r") as f:
        content = f.read()

    assert "proxy_pass http://127.0.0.1:8081" in content, (
        "Nginx config was not updated correctly. It should proxy traffic to 127.0.0.1:8081."
    )
    assert "8099" not in content, "The deliberate typo (8099) is still present in the Nginx config."

    result = subprocess.run(
        ["nginx", "-t", "-c", CONF_PATH, "-p", "/home/user/nginx"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert result.returncode == 0, f"Nginx configuration is not valid:\n{result.stdout}\n{result.stderr}"


def test_run_job_sh_fixed():
    assert os.path.isfile(JOB_PATH), f"File {JOB_PATH} is missing."
    with open(JOB_PATH, "r") as f:
        content = f.read()

    assert "REPORT_DIR=/home/user/app_data" in content, "REPORT_DIR is not correctly set in run_job.sh"
    assert "TZ=UTC" in content, "TZ=UTC is not set in run_job.sh"
    assert "LC_ALL=C" in content, "LC_ALL=C is not set in run_job.sh"


def test_required_services_are_running_as_user():
    user_uid = pwd.getpwnam("user").pw_uid

    backend = matching_processes(["python3", "/home/user/backend/server.py"])
    assert backend, "The required backend server process is not running."
    assert any(uid == user_uid for _, uid, _ in backend), "The backend was not started as the local user."

    nginx = matching_processes(["nginx", "-c", "/home/user/nginx/nginx.conf", "-p", "/home/user/nginx"])
    assert nginx, "Nginx was not started with the required configuration and prefix."
    assert any(uid == user_uid for _, uid, _ in nginx), "Nginx was not started as the local user."


def test_report_json_exists_and_valid():
    assert os.path.isfile(REPORT_PATH), f"Report file {REPORT_PATH} was not generated."
    with open(REPORT_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {REPORT_PATH} does not contain valid JSON.")

    assert "generated_at" in data, "Report JSON is missing 'generated_at' field."
    assert "UTC" in data["generated_at"], (
        f"Timestamp '{data['generated_at']}' does not contain 'UTC'. "
        "The environment variables for the job script were likely not applied correctly."
    )


def test_success_response_txt_is_exact_live_proxy_output():
    assert os.path.isfile(RESPONSE_PATH), f"Success response file {RESPONSE_PATH} is missing."
    with open(RESPONSE_PATH, "rb") as f:
        content = f.read()

    assert content, f"File {RESPONSE_PATH} is empty."
    try:
        data = json.loads(content)
    except json.JSONDecodeError:
        pytest.fail(f"File {RESPONSE_PATH} does not contain valid JSON.")

    assert data.get("status") == "success", f"Expected status 'success', got {data.get('status')}"
    assert "data" in data, "Response JSON is missing the 'data' field."
    assert "metrics" in data["data"], "Response JSON is missing 'metrics' inside 'data'."

    live = curl("http://127.0.0.1:8080/api/report")
    assert content == live, (
        "success_response.txt is not the exact output currently returned by "
        "curl http://127.0.0.1:8080/api/report"
    )


def test_job_and_stack_work_end_to_end_from_clean_environment():
    # Force the submitted wrapper to recreate the report without inheriting any
    # REPORT_DIR, TZ, or locale settings from the verifier.
    for path in (REPORT_PATH, "/tmp/fallback_dir/report.json"):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    started = time.time()
    result = subprocess.run(
        [
            "runuser", "-u", "user", "--", "env", "-i",
            "HOME=/home/user", "PATH=/usr/local/bin:/usr/bin:/bin",
            JOB_PATH,
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, f"run_job.sh failed:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(REPORT_PATH), "run_job.sh did not recreate the report at REPORT_DIR."
    assert os.stat(REPORT_PATH).st_mtime >= started - 1, "The report was not freshly generated by run_job.sh."
    assert not os.path.exists("/tmp/fallback_dir/report.json"), "The job still wrote to its fallback directory."

    with open(REPORT_PATH, "r") as f:
        report = json.load(f)

    assert report.get("metrics") == {"cpu": 45, "memory": 1024}, "The generated report metrics are incorrect."
    timestamp = report.get("generated_at")
    assert isinstance(timestamp, str), "The generated report has no timestamp string."
    assert re.fullmatch(
        r"(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday), "
        r"\d{2} (January|February|March|April|May|June|July|August|September|October|November|December) "
        r"\d{4} \d{2}:\d{2}:\d{2} UTC",
        timestamp,
    ), f"Timestamp is not in the required C-locale UTC format: {timestamp!r}"

    old_locale = locale.setlocale(locale.LC_TIME)
    try:
        locale.setlocale(locale.LC_TIME, "C")
        generated = datetime.datetime.strptime(timestamp, "%A, %d %B %Y %H:%M:%S UTC")
    finally:
        locale.setlocale(locale.LC_TIME, old_locale)
    generated = generated.replace(tzinfo=datetime.timezone.utc).timestamp()
    assert abs(time.time() - generated) < 120, "The generated UTC timestamp is not current."

    expected = json.dumps({"status": "success", "data": report}).encode("utf-8")
    direct = curl("http://127.0.0.1:8081/report")
    proxied = curl("http://127.0.0.1:8080/api/report")
    assert direct == expected, "The backend did not serve the freshly generated report."
    assert proxied == expected, "Nginx did not proxy /api/report to the backend correctly."

    # A per-verification value ensures neither endpoint is merely serving a
    # prebuilt success payload.
    report["verifier_nonce"] = os.urandom(16).hex()
    with open(REPORT_PATH, "w") as f:
        json.dump(report, f)
    expected_nonce = json.dumps({"status": "success", "data": report}).encode("utf-8")
    assert curl("http://127.0.0.1:8081/report") == expected_nonce
    assert curl("http://127.0.0.1:8080/api/report") == expected_nonce
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
