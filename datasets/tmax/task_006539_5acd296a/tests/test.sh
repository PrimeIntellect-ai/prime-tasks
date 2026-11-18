#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import re
import secrets
import signal
import subprocess
import time
from pathlib import Path

import pytest

USER = "user"
HOME = "/home/user"
UID = pwd.getpwnam(USER).pw_uid
USER_ENV = [
    f"HOME={HOME}",
    f"USER={USER}",
    f"LOGNAME={USER}",
    f"XDG_RUNTIME_DIR=/run/user/{UID}",
    f"DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/{UID}/bus",
]


def run_as_user(argv, **kwargs):
    return subprocess.run(["runuser", "-u", USER, "--", "env", *USER_ENV, *argv], **kwargs)


def systemctl(*args, check=True):
    return run_as_user(
        ["systemctl", "--user", *args],
        check=check,
        capture_output=True,
        text=True,
    )


def curl(url):
    return subprocess.run(
        ["curl", "--fail", "--silent", "--show-error", "--max-time", "3", url],
        check=True,
        capture_output=True,
        text=True,
    ).stdout


def wait_for_url(url, expected=None, timeout=10):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            body = curl(url)
            if expected is None or body.strip() == expected:
                return body
            last_error = AssertionError(f"unexpected response: {body!r}")
        except Exception as exc:
            last_error = exc
        time.sleep(0.2)
    raise AssertionError(f"Timed out waiting for {url}: {last_error}")


def test_proxy_cpp_fixed():
    path = "/home/user/src/proxy.cpp"
    assert os.path.isfile(path), f"File {path} is missing."
    with open(path, "r") as f:
        content = f.read()
    assert "htons(8080)" in content, "proxy.cpp does not bind to port 8080. You need to change htons(80) to htons(8080)."


def test_backends_conf_content():
    path = "/home/user/proxy_config/backends.conf"
    assert os.path.isfile(path), f"File {path} is missing. Did the mount script run correctly?"
    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]
    assert len(lines) == 1, f"backends.conf should contain exactly one line, found {len(lines)}."
    assert lines[0] == "127.0.0.1:9001", f"backends.conf does not contain the correct IP:PORT. Found: {lines[0]}"


def assert_nobody_read_acl(path):
    try:
        result = subprocess.run(["getfacl", path], capture_output=True, text=True, check=True)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to run getfacl on {path}: {e}")

    acl_output = result.stdout
    has_read = False
    for line in acl_output.splitlines():
        if line.startswith("user:nobody:") and len(line) >= 13 and line[12] == "r":
            has_read = True
            break
    assert has_read, f"ACL for user 'nobody' does not grant read access. getfacl output:\n{acl_output}"


def test_acl_set_correctly():
    path = "/home/user/proxy_config/backends.conf"
    assert os.path.isfile(path), f"File {path} is missing."
    assert_nobody_read_acl(path)


def test_final_output_file():
    path = "/home/user/final_proxy_output.txt"
    assert os.path.isfile(path), f"File {path} is missing. Did you save the curl output?"
    with open(path, "r") as f:
        content = f.read().strip()
    assert "Hello from backend!" in content, "final_proxy_output.txt does not contain the expected response from the proxy."


def test_scripts_binary_service_and_forwarding():
    log_path = Path("/home/user/logs/backend_startup.log")
    raw_conf = Path("/home/user/raw_config/backends.conf")
    mounted_conf = Path("/home/user/proxy_config/backends.conf")
    extract_script = "/home/user/scripts/extract_backends.sh"
    mount_script = "/home/user/scripts/mount_config.sh"
    fstab_path = Path("/home/user/scripts/fstab.proxy")

    assert os.path.isfile(extract_script) and os.access(extract_script, os.X_OK), "extract_backends.sh is missing or not executable"
    assert os.path.isfile(mount_script) and os.access(mount_script, os.X_OK), "mount_config.sh is missing or not executable"

    fields = fstab_path.read_text().split()
    assert len(fields) == 6, "fstab.proxy must contain one standard six-field fstab entry"
    assert fields[0] == "/home/user/raw_config", "fstab.proxy has the wrong source"
    assert fields[1] == "/home/user/proxy_config", "fstab.proxy has the wrong destination"
    assert fields[2] == "bind", "fstab.proxy must use bind as required by mount_config.sh"

    original_log = log_path.read_bytes()
    marker = Path(f"/home/user/raw_config/.mount-check-{secrets.token_hex(8)}")
    mounted_marker = Path("/home/user/proxy_config") / marker.name
    a = 10000 + secrets.randbelow(10000)
    b = 30000 + secrets.randbelow(10000)
    expected_dynamic = [f"127.0.0.1:{a}", f"10.23.45.67:{b}"]

    try:
        log_path.write_text(
            "[INFO] unrelated 192.0.2.1:1111\n"
            f"[INFO] Server alpha started successfully at {expected_dynamic[0]}\n"
            "[ERROR] Server bad failed to bind at 203.0.113.8:2222\n"
            f"[INFO] Server beta started successfully at {expected_dynamic[1]}\n"
        )
        run_as_user([extract_script], check=True, capture_output=True, text=True)
        generated = [line.strip() for line in raw_conf.read_text().splitlines() if line.strip()]
        assert generated == expected_dynamic, f"extract_backends.sh produced {generated}, expected {expected_dynamic}"
        assert all(re.fullmatch(r"(?:\d{1,3}\.){3}\d{1,3}:\d+", line) for line in generated)
    finally:
        log_path.write_bytes(original_log)

    # Regenerate the real configuration and execute the repaired mount pipeline.
    run_as_user([extract_script], check=True, capture_output=True, text=True)
    assert raw_conf.read_text().splitlines() == ["127.0.0.1:9001"]
    marker.write_text(secrets.token_hex(16))
    try:
        run_as_user([mount_script], check=True, capture_output=True, text=True)
        assert mounted_marker.is_file(), "mount_config.sh did not copy data from raw_config to proxy_config"
        assert mounted_marker.read_text() == marker.read_text()
    finally:
        marker.unlink(missing_ok=True)
        mounted_marker.unlink(missing_ok=True)

    assert mounted_conf.read_text().splitlines() == ["127.0.0.1:9001"]
    assert_nobody_read_acl(str(mounted_conf))

    source = "/home/user/src/proxy.cpp"
    binary = "/home/user/bin/proxy"
    compile_result = run_as_user(
        ["g++", "-std=c++17", source, "-o", binary, "-lpthread"],
        capture_output=True,
        text=True,
    )
    assert compile_result.returncode == 0, f"proxy.cpp does not compile:\n{compile_result.stdout}\n{compile_result.stderr}"
    assert os.path.isfile(binary) and os.access(binary, os.X_OK), "/home/user/bin/proxy is not an executable file"
    with open(binary, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/bin/proxy is not an ELF executable"

    # Stop stale instances, launch an unpredictable backend response, and require
    # the systemd-managed submitted proxy to return that response through port 8080.
    systemctl("stop", "proxy-manager.service", check=False)
    subprocess.run(["pkill", "-u", USER, "-x", "proxy"], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-u", USER, "-f", "python3 -m http.server 9001"], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.3)

    token = "backend-" + secrets.token_hex(24)
    dynamic_www = Path("/tmp") / ("proxy-backend-" + secrets.token_hex(8))
    dynamic_www.mkdir(mode=0o755)
    (dynamic_www / "index.html").write_text(token + "\n")
    os.chmod(dynamic_www / "index.html", 0o644)

    backend = subprocess.Popen(
        ["runuser", "-u", USER, "--", "python3", "-m", "http.server", "9001", "--bind", "127.0.0.1", "--directory", str(dynamic_www)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    try:
        wait_for_url("http://127.0.0.1:9001", expected=token)
        reload_result = systemctl("daemon-reload", check=False)
        assert reload_result.returncode == 0, f"systemctl --user daemon-reload failed: {reload_result.stderr}"
        start_result = systemctl("start", "proxy-manager.service", check=False)
        assert start_result.returncode == 0, f"proxy-manager.service failed to start: {start_result.stderr}"
        active = systemctl("is-active", "proxy-manager.service", check=False)
        assert active.returncode == 0 and active.stdout.strip() == "active", f"proxy-manager.service is not active: {active.stdout} {active.stderr}"
        body = wait_for_url("http://127.0.0.1:8080", expected=token)
        assert body.strip() == token, "The proxy returned a fabricated response instead of forwarding the backend response"
    finally:
        try:
            os.killpg(backend.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            backend.wait(timeout=3)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(backend.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        subprocess.Popen(
            ["runuser", "-u", USER, "--", "python3", "-m", "http.server", "9001", "--bind", "127.0.0.1", "--directory", "/home/user/www"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
