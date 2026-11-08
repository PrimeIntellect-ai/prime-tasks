#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pwd
import re
import subprocess
import time
import urllib.error
import urllib.request


def test_symlinks_and_dirs():
    app_dir = "/home/user/app"
    conf_symlink = os.path.join(app_dir, "conf")
    logs_symlink = os.path.join(app_dir, "logs")
    internal_conf = os.path.join(app_dir, "internal_conf")
    local_logs = os.path.join(app_dir, "local_logs")

    assert os.path.isdir(internal_conf), f"Target directory {internal_conf} does not exist."
    assert os.path.isdir(local_logs), f"Target directory {local_logs} does not exist."

    assert os.path.islink(conf_symlink), f"{conf_symlink} is not a symlink."
    assert os.readlink(conf_symlink) == internal_conf, f"{conf_symlink} does not point to {internal_conf}."

    assert os.path.islink(logs_symlink), f"{logs_symlink} is not a symlink."
    assert os.readlink(logs_symlink) == local_logs, f"{logs_symlink} does not point to {local_logs}."


def test_backends_json():
    backends_path = "/home/user/app/conf/backends.json"
    assert os.path.isfile(backends_path), f"Configuration file {backends_path} does not exist."

    with open(backends_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{backends_path} does not contain valid JSON."

    expected = ["http://127.0.0.1:8081", "http://127.0.0.1:8082"]
    assert data == expected, f"Contents of {backends_path} do not match expected array."


def _demote_to_user():
    account = pwd.getpwnam("user")

    def demote():
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    return demote


def _run_ci_expect_failure(script_path, status_file):
    if os.path.lexists(status_file):
        os.remove(status_file)
    result = subprocess.run(
        [script_path],
        capture_output=True,
        text=True,
        preexec_fn=_demote_to_user(),
    )
    assert result.returncode == 1, (
        f"{script_path} must exit 1 for an invalid deployment state; got "
        f"{result.returncode}. stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert os.path.isfile(status_file), f"{status_file} was not created on failure."
    with open(status_file, "r") as f:
        status = f.read().strip()
    assert status == "PIPELINE_FAILED", f"Expected PIPELINE_FAILED, got {status!r}."


def test_ci_cd_verify():
    script_path = "/home/user/ci_cd_verify.sh"
    status_file = "/home/user/deploy_status.txt"
    conf_path = "/home/user/app/conf"
    logs_path = "/home/user/app/logs"
    backends_path = "/home/user/app/internal_conf/backends.json"

    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

    with open(script_path, "r") as f:
        script_text = f.read()
    has_set_e = re.search(r"(?m)^[ \t]*set[ \t]+-[A-Za-z]*e[A-Za-z]*(?:[ \t;]|$)", script_text)
    has_errexit = re.search(r"(?m)^[ \t]*set[ \t]+-o[ \t]+errexit(?:[ \t;]|$)", script_text)
    assert has_set_e or has_errexit, f"{script_path} does not enable strict error handling with set -e."

    if os.path.exists(status_file):
        os.remove(status_file)

    result = subprocess.run([script_path], capture_output=True, text=True)
    assert result.returncode == 0, f"{script_path} failed with exit code {result.returncode}. Output: {result.stderr}"

    assert os.path.isfile(status_file), f"{status_file} was not created by the script."
    with open(status_file, "r") as f:
        status = f.read().strip()
    assert status == "PIPELINE_SUCCESS", f"Expected PIPELINE_SUCCESS in {status_file}, got '{status}'."

    # A broken configuration-directory symlink must be detected.
    original_conf_target = os.readlink(conf_path)
    os.unlink(conf_path)
    os.symlink("/definitely/missing/conf-target", conf_path)
    try:
        _run_ci_expect_failure(script_path, status_file)
    finally:
        os.unlink(conf_path)
        os.symlink(original_conf_target, conf_path)

    # A broken logs-directory symlink must also be detected.
    original_logs_target = os.readlink(logs_path)
    os.unlink(logs_path)
    os.symlink("/definitely/missing/log-target", logs_path)
    try:
        _run_ci_expect_failure(script_path, status_file)
    finally:
        os.unlink(logs_path)
        os.symlink(original_logs_target, logs_path)

    # Missing and unreadable configuration files must produce the required failure.
    saved_path = backends_path + ".verifier_saved"
    assert not os.path.lexists(saved_path), f"Unexpected verifier temporary path {saved_path}."
    os.rename(backends_path, saved_path)
    try:
        _run_ci_expect_failure(script_path, status_file)
    finally:
        os.rename(saved_path, backends_path)

    original_mode = os.stat(backends_path).st_mode & 0o7777
    os.chmod(backends_path, 0)
    try:
        _run_ci_expect_failure(script_path, status_file)
    finally:
        os.chmod(backends_path, original_mode)


def _stop_process(process):
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)


def test_proxy_js():
    proxy_script = "/home/user/app/proxy.js"
    pid_file = "/home/user/app/logs/proxy.pid"
    backends_path = "/home/user/app/internal_conf/backends.json"

    assert os.path.isfile(proxy_script), f"Proxy script {proxy_script} does not exist."

    # Verify that proxy.js actually loads and parses backends.json rather than ignoring it.
    with open(backends_path, "rb") as f:
        original_config = f.read()
    if os.path.lexists(pid_file):
        os.remove(pid_file)
    with open(backends_path, "w") as f:
        f.write("this is deliberately invalid JSON")

    invalid_process = subprocess.Popen(
        ["node", proxy_script], stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    try:
        try:
            invalid_process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            _stop_process(invalid_process)
            assert False, "proxy.js stayed running even though backends.json was invalid."
        assert invalid_process.returncode != 0, "proxy.js must fail when backends.json cannot be parsed."
        assert not os.path.exists(pid_file), "proxy.js wrote a PID despite failing to load its configuration."
    finally:
        _stop_process(invalid_process)
        with open(backends_path, "wb") as f:
            f.write(original_config)
        if os.path.lexists(pid_file):
            os.remove(pid_file)

    process = subprocess.Popen(["node", proxy_script], stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    try:
        time.sleep(2)
        assert process.poll() is None, f"Proxy script exited prematurely with code {process.returncode}."

        try:
            req = urllib.request.Request("http://127.0.0.1:8080")
            with urllib.request.urlopen(req, timeout=5) as response:
                assert response.status == 200, f"Expected HTTP 200, got {response.status}"
                body = response.read().decode("utf-8").strip()
                assert body == "PROXY_ACTIVE", f"Expected response 'PROXY_ACTIVE', got '{body}'"
        except urllib.error.URLError as e:
            assert False, f"Failed to connect to proxy server: {e}"

        assert os.path.isfile(pid_file), f"PID file {pid_file} was not created."
        with open(pid_file, "r") as f:
            pid_str = f.read().strip()
            assert pid_str.isdigit(), f"PID file {pid_file} does not contain a valid numeric PID."
            assert int(pid_str) == process.pid, (
                f"PID file contains {pid_str}, but the started proxy process PID is {process.pid}."
            )
    finally:
        _stop_process(process)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
