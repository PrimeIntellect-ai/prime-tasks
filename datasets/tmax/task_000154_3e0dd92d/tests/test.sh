#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import random
import re
import socket
import stat
import string
import subprocess
import tempfile
import time
import pytest


def test_stage1_outage_seconds():
    outage_file = "/home/user/outage_seconds.txt"
    assert os.path.exists(outage_file), f"File {outage_file} does not exist. Stage 1 incomplete."

    with open(outage_file, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = ["12", "13", "14", "15", "42", "43", "44", "45", "46", "47"]
    assert lines == expected_lines, f"Expected timestamps {expected_lines}, but got {lines}. Video analysis incorrect."


def socket_identity(path):
    st = os.stat(path)
    return (st.st_ino, st.st_ctime_ns)


def wait_for_socket(path, timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            st = os.stat(path)
            if stat.S_ISSOCK(st.st_mode):
                return st
        except FileNotFoundError:
            pass
        time.sleep(0.1)
    pytest.fail(f"Socket {path} was not recreated after service restart.")


def assert_www_data_can_connect(sock_path):
    account = pwd.getpwnam("www-data")

    def demote():
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    code = (
        "import socket; "
        f"s=socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); s.settimeout(3); s.connect({sock_path!r}); s.close()"
    )
    result = subprocess.run(
        ["python3", "-c", code],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=5,
        preexec_fn=demote,
    )
    assert result.returncode == 0, (
        f"www-data could not connect to {sock_path}: {result.stderr.strip()}"
    )


def test_stage2_socket_permissions():
    sock_path = "/run/api-backend/api.sock"
    assert os.path.exists(sock_path), f"Socket {sock_path} does not exist. Backend service may not be running."

    st = os.stat(sock_path)

    try:
        www_data_uid = pwd.getpwnam("www-data").pw_uid
        www_data_gid = pwd.getpwnam("www-data").pw_gid
    except KeyError:
        pytest.fail("User www-data does not exist on the system.")

    can_read = False
    can_write = False

    if st.st_uid == www_data_uid:
        can_read = bool(st.st_mode & stat.S_IRUSR)
        can_write = bool(st.st_mode & stat.S_IWUSR)
    elif st.st_gid == www_data_gid:
        can_read = bool(st.st_mode & stat.S_IRGRP)
        can_write = bool(st.st_mode & stat.S_IWGRP)
    else:
        can_read = bool(st.st_mode & stat.S_IROTH)
        can_write = bool(st.st_mode & stat.S_IWOTH)

    assert can_read and can_write, f"www-data does not have rw permissions on {sock_path}. Nginx will still return 502."
    assert stat.S_ISSOCK(st.st_mode), f"{sock_path} is not a UNIX socket."


def test_stage2_persistent_restart_and_deployment():
    sock_path = "/run/api-backend/api.sock"
    deploy_path = "/home/user/deploy.sh"
    service_path = "/etc/systemd/system/api-backend.service"

    assert os.path.isfile(deploy_path), f"Deployment script {deploy_path} does not exist."
    assert os.path.isfile(service_path), f"Service definition {service_path} does not exist."

    with open(deploy_path, "r", errors="replace") as f:
        deploy_text = f.read()
    assert re.search(r"\bnginx\b", deploy_text), "deploy.sh does not manage Nginx."
    assert re.search(r"\bapi-backend(?:\.service)?\b", deploy_text), "deploy.sh does not manage the backend service."

    before_deploy = socket_identity(sock_path)
    deployed = subprocess.run(
        ["/bin/bash", deploy_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert deployed.returncode == 0, f"deploy.sh failed: {deployed.stderr.strip()}"
    after_deploy = wait_for_socket(sock_path)
    assert (after_deploy.st_ino, after_deploy.st_ctime_ns) != before_deploy, (
        "deploy.sh did not recreate the backend socket; the backend was not restarted."
    )

    subprocess.run(["systemctl", "daemon-reload"], check=True, timeout=10)
    before_restart = socket_identity(sock_path)
    restarted = subprocess.run(
        ["systemctl", "restart", "api-backend.service"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert restarted.returncode == 0, f"Backend service restart failed: {restarted.stderr.strip()}"
    after_restart = wait_for_socket(sock_path)
    assert (after_restart.st_ino, after_restart.st_ctime_ns) != before_restart, (
        "A direct service restart did not recreate the backend socket."
    )

    active = subprocess.run(
        ["systemctl", "is-active", "api-backend.service"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=5,
    )
    assert active.returncode == 0 and active.stdout.strip() == "active", "api-backend.service is not active."

    nginx_test = subprocess.run(
        ["nginx", "-t"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=10
    )
    assert nginx_test.returncode == 0, f"Nginx configuration is invalid: {nginx_test.stderr.strip()}"
    nginx_dump = subprocess.run(
        ["nginx", "-T"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=10
    )
    combined = nginx_dump.stdout + nginx_dump.stderr
    assert nginx_dump.returncode == 0
    assert re.search(r"proxy_pass\s+http://unix:/run/api-backend/api\.sock\s*;", combined), (
        "Nginx is not configured to route requests to the backend UNIX socket."
    )

    assert_www_data_can_connect(sock_path)
    wait_for_socket(sock_path)


def run_sanitizer(path, request):
    try:
        result = subprocess.run(
            [path], input=request, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=3
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Sanitizer {path} hung while reading a complete request from stdin.")
    return result.returncode


def test_stage3_sanitizer_adversarial_corpus():
    sanitizer_path = "/home/user/sanitizer"
    assert os.path.exists(sanitizer_path), f"Sanitizer binary {sanitizer_path} does not exist."
    assert os.access(sanitizer_path, os.X_OK), f"Sanitizer {sanitizer_path} is not executable."
    assert os.path.isfile(sanitizer_path), f"Sanitizer {sanitizer_path} is not a regular file."
    with open(sanitizer_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Sanitizer is not a compiled native executable."

    evil_dir = "/app/corpora/evil/"
    clean_dir = "/app/corpora/clean/"

    assert os.path.isdir(evil_dir), f"Evil corpus missing at {evil_dir}"
    assert os.path.isdir(clean_dir), f"Clean corpus missing at {clean_dir}"

    evil_files = os.listdir(evil_dir)
    clean_files = os.listdir(clean_dir)

    evil_bypassed = []
    clean_modified = []

    for filename in evil_files:
        filepath = os.path.join(evil_dir, filename)
        with open(filepath, "rb") as f:
            result = subprocess.run([sanitizer_path], stdin=f)
            if result.returncode != 1:
                evil_bypassed.append(filename)

    for filename in clean_files:
        filepath = os.path.join(clean_dir, filename)
        with open(filepath, "rb") as f:
            result = subprocess.run([sanitizer_path], stdin=f)
            if result.returncode != 0:
                clean_modified.append(filename)

    error_msg = []
    if evil_bypassed:
        error_msg.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        error_msg.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")

    if error_msg:
        pytest.fail(" | ".join(error_msg))


def make_request(header_name=None, value=None, extra_headers=()):
    lines = ["GET /generated HTTP/1.1", "Host: verifier.invalid"]
    if header_name is not None:
        lines.append(f"{header_name}: {value}")
    lines.extend(extra_headers)
    return ("\r\n".join(lines) + "\r\n\r\n").encode()


def test_stage3_generated_policy_and_source():
    source_path = "/home/user/sanitizer.c"
    binary_path = "/home/user/sanitizer"
    assert os.path.isfile(source_path), f"C source {source_path} does not exist."

    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "sanitizer")
        compiled = subprocess.run(
            ["gcc", source_path, "-o", rebuilt],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
        assert compiled.returncode == 0, f"sanitizer.c does not compile: {compiled.stderr.strip()}"

        alphabet = string.ascii_letters + string.digits + "-"
        valid64 = "".join(random.SystemRandom().choice(alphabet) for _ in range(64))
        valid_random = "".join(random.SystemRandom().choice(alphabet) for _ in range(random.randint(8, 55)))
        too_long = "".join(random.SystemRandom().choice(string.ascii_letters + string.digits) for _ in range(65 + random.randint(0, 20)))
        bad_base = "".join(random.SystemRandom().choice(string.ascii_letters + string.digits) for _ in range(20))
        pos = random.randint(1, len(bad_base) - 1)
        bad_char = random.SystemRandom().choice(["_", "@", ".", "/", "+", "$"])
        bad_value = bad_base[:pos] + bad_char + bad_base[pos:]

        safe = [
            make_request(),
            make_request("X-Trace-Id", ""),
            make_request("X-Trace-Id", valid_random),
            make_request("X-Trace-Id", valid64),
            make_request("x-trace-id", "abc-123-XYZ"),
            make_request("X-Trace-Identity", bad_value),
        ]
        evil = [
            make_request("X-Trace-Id", too_long),
            make_request("X-Trace-Id", bad_value),
            make_request("x-trace-id", bad_value),
            make_request("X-TRACE-ID", too_long),
            make_request("X-Trace-Id", valid_random, (f"X-Trace-Id: {bad_value}",)),
        ]

        for candidate in (binary_path, rebuilt):
            for index, request in enumerate(safe):
                assert run_sanitizer(candidate, request) == 0, (
                    f"{candidate} rejected generated safe request {index}."
                )
            for index, request in enumerate(evil):
                assert run_sanitizer(candidate, request) == 1, (
                    f"{candidate} accepted generated malicious request {index}."
                )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
