#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pwd
import re
import secrets
import signal
import socket
import ssl
import string
import subprocess
import tempfile
import time
import urllib.request

import pytest

HOME = "/home/user"
RUN_LOG = f"{HOME}/run.log"


def read_run_log():
    with open(RUN_LOG, "r") as f:
        content = f.read()
    py = re.search(r"^PYTHON_PID=(\d+)$", content, re.MULTILINE)
    socat = re.search(r"^SOCAT_PID=(\d+)$", content, re.MULTILINE)
    assert py, "PYTHON_PID not found or invalid in run.log."
    assert socat, "SOCAT_PID not found or invalid in run.log."
    return content, int(py.group(1)), int(socat.group(1))


def proc_cmdline(pid):
    with open(f"/proc/{pid}/cmdline", "rb") as f:
        return f.read().replace(b"\0", b" ").decode("utf-8", "replace").strip()


def proc_uid(pid):
    return os.stat(f"/proc/{pid}").st_uid


def listener_inodes(port):
    result = set()
    for path in ("/proc/net/tcp", "/proc/net/tcp6"):
        with open(path, "r") as f:
            next(f)
            for line in f:
                fields = line.split()
                if len(fields) >= 10:
                    local = fields[1]
                    state = fields[3]
                    inode = fields[9]
                    if state == "0A" and int(local.rsplit(":", 1)[1], 16) == port:
                        result.add(inode)
    return result


def pid_socket_inodes(pid):
    result = set()
    fd_dir = f"/proc/{pid}/fd"
    for name in os.listdir(fd_dir):
        try:
            target = os.readlink(os.path.join(fd_dir, name))
        except OSError:
            continue
        match = re.fullmatch(r"socket:\[(\d+)\]", target)
        if match:
            result.add(match.group(1))
    return result


def wait_for_listener(pid, port, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            if listener_inodes(port) & pid_socket_inodes(pid):
                return
        except (FileNotFoundError, ProcessLookupError):
            pass
        time.sleep(0.1)
    pytest.fail(f"PID {pid} does not own a listening socket on port {port}.")


def run_as_user(argv, timeout=15):
    account = pwd.getpwnam("user")

    def demote():
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    env = os.environ.copy()
    env["HOME"] = HOME
    env["USER"] = "user"
    env["LOGNAME"] = "user"
    return subprocess.run(
        argv,
        cwd=HOME,
        env=env,
        preexec_fn=demote,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
    )


def test_directories_exist():
    assert os.path.isdir("/home/user/certs"), "Directory /home/user/certs does not exist."
    assert os.path.isdir("/home/user/edge_data"), "Directory /home/user/edge_data does not exist."


def test_certificates_exist():
    assert os.path.isfile("/home/user/certs/edge.crt"), "Certificate file /home/user/certs/edge.crt does not exist."
    assert os.path.isfile("/home/user/certs/edge.key"), "Key file /home/user/certs/edge.key does not exist."


def test_certificate_properties():
    cert = "/home/user/certs/edge.crt"
    key = "/home/user/certs/edge.key"

    text = subprocess.run(
        ["openssl", "x509", "-in", cert, "-noout", "-text", "-subject", "-nameopt", "RFC2253"],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    ).stdout
    assert re.search(r"Public-Key:\s*\(2048 bit\)", text), "Certificate does not use a 2048-bit RSA key."
    subject_lines = [line.strip() for line in text.splitlines() if line.strip().startswith("subject=")]
    assert subject_lines, "Certificate subject is missing."
    subject = subject_lines[-1].split("=", 1)[1]
    assert re.search(r"(?:^|,)CN=localhost(?:,|$)", subject), "Certificate CN is not localhost."

    key_check = subprocess.run(
        ["openssl", "pkey", "-in", key, "-noout"],
        stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    assert key_check.returncode == 0, "Private key is invalid or encrypted."

    cert_pub = subprocess.run(
        ["openssl", "x509", "-in", cert, "-pubkey", "-noout"],
        check=True, stdout=subprocess.PIPE
    ).stdout
    key_pub = subprocess.run(
        ["openssl", "pkey", "-in", key, "-pubout"],
        check=True, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE
    ).stdout
    assert cert_pub == key_pub, "Certificate and private key do not match."


def test_deploy_script_executable():
    assert os.path.isfile("/home/user/deploy.sh"), "Deploy script /home/user/deploy.sh does not exist."
    assert os.access("/home/user/deploy.sh", os.X_OK), "Deploy script /home/user/deploy.sh is not executable."


def test_c_utility_compiles_and_handles_varied_inputs():
    source = "/home/user/iot_setup.c"
    assert os.path.isfile(source), "C source /home/user/iot_setup.c does not exist."

    with tempfile.TemporaryDirectory() as td:
        binary = os.path.join(td, "iot_setup_test")
        compiled = subprocess.run(
            ["gcc", source, "-o", binary],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        assert compiled.returncode == 0, f"iot_setup.c failed to compile: {compiled.stderr}"

        alphabet = string.ascii_letters + string.digits + "-_ "
        cases = [
            ("dev-" + secrets.token_hex(8), "sensor-" + secrets.token_hex(7)),
            ("".join(secrets.choice(alphabet) for _ in range(50)),
             "".join(secrets.choice(alphabet) for _ in range(50))),
        ]
        config_path = "/home/user/edge_data/config.json"
        old = None
        if os.path.exists(config_path):
            with open(config_path, "rb") as f:
                old = f.read()
        try:
            for device, sensor in cases:
                result = subprocess.run(
                    [binary], input=f"{device}\n{sensor}\nignored-third-line\n",
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=5
                )
                assert result.returncode == 0, "Compiled C utility exited unsuccessfully."
                with open(config_path, "rb") as f:
                    actual = f.read()
                expected = f'{{"device_id": "{device}", "sensor": "{sensor}"}}'.encode()
                assert actual == expected, "C utility did not emit the exact JSON for varied input."
        finally:
            if old is not None:
                with open(config_path, "wb") as f:
                    f.write(old)


def test_deployment_script_actually_builds_and_launches_services():
    user_uid = pwd.getpwnam("user").pw_uid

    if os.path.isfile(RUN_LOG):
        try:
            _, old_py, old_socat = read_run_log()
            for pid in (old_py, old_socat):
                try:
                    if pid > 100 and proc_uid(pid) == user_uid:
                        os.kill(pid, signal.SIGTERM)
                except (FileNotFoundError, ProcessLookupError, PermissionError):
                    pass
        except Exception:
            pass

    time.sleep(0.5)
    executable = "/home/user/iot_setup"
    try:
        os.unlink(executable)
    except FileNotFoundError:
        pass

    started = time.time()
    result = run_as_user(["/home/user/deploy.sh"])
    assert result.returncode == 0, f"deploy.sh failed: {result.stderr}"
    assert os.path.isfile(executable), "deploy.sh did not compile /home/user/iot_setup."
    assert os.access(executable, os.X_OK), "/home/user/iot_setup is not executable."
    assert os.path.getmtime(executable) >= started - 1, "iot_setup executable was not freshly built by deploy.sh."
    assert os.path.isfile(RUN_LOG), "deploy.sh did not create run.log."
    assert os.path.getmtime(RUN_LOG) >= started - 1, "deploy.sh did not refresh run.log."


def test_config_json_content():
    config_path = "/home/user/edge_data/config.json"
    assert os.path.isfile(config_path), f"Config file {config_path} does not exist."
    with open(config_path, "r") as f:
        content = f.read()
    try:
        data = json.loads(content)
    except json.JSONDecodeError:
        pytest.fail(f"File {config_path} does not contain valid JSON.")

    assert data.get("device_id") == "Gateway-Alpha", "device_id in config.json is not 'Gateway-Alpha'."
    assert data.get("sensor") == "Humidity", "sensor in config.json is not 'Humidity'."
    assert content == '{"device_id": "Gateway-Alpha", "sensor": "Humidity"}', "config.json format is not exact."


def test_run_log_content():
    assert os.path.isfile(RUN_LOG), f"Log file {RUN_LOG} does not exist."
    content, _, _ = read_run_log()
    assert re.fullmatch(r"PYTHON_PID=\d+\nSOCAT_PID=\d+\n?", content), "run.log is not in the exact required format."


def test_recorded_pids_are_the_required_live_services():
    _, py_pid, socat_pid = read_run_log()
    user_uid = pwd.getpwnam("user").pw_uid

    assert proc_uid(py_pid) == user_uid, "Recorded Python PID is not owned by user."
    assert proc_uid(socat_pid) == user_uid, "Recorded socat PID is not owned by user."

    py_cmd = proc_cmdline(py_pid)
    socat_cmd = proc_cmdline(socat_pid)
    py_exe = os.path.basename(os.readlink(f"/proc/{py_pid}/exe"))
    socat_exe = os.path.basename(os.readlink(f"/proc/{socat_pid}/exe"))

    assert py_exe.startswith("python"), "Recorded PYTHON_PID is not a Python process."
    assert "http.server" in py_cmd and re.search(r"(?:^|\s)8080(?:\s|$)", py_cmd), "Python PID is not the port 8080 HTTP server."
    py_cwd = os.path.realpath(f"/proc/{py_pid}/cwd")
    assert py_cwd == "/home/user/edge_data" or "/home/user/edge_data" in py_cmd, "Python server is not serving edge_data."

    assert socat_exe == "socat", "Recorded SOCAT_PID is not a socat process."
    lower = socat_cmd.lower()
    assert "8443" in lower and "openssl-listen" in lower, "socat is not an OpenSSL listener on port 8443."
    assert "/home/user/certs/edge.crt" in socat_cmd, "socat does not use edge.crt."
    assert "/home/user/certs/edge.key" in socat_cmd, "socat does not use edge.key."
    assert re.search(r"verify\s*=\s*0", lower), "socat TLS listener does not set verify=0."
    assert "localhost" in lower and "8080" in lower, "socat does not forward to localhost:8080."

    wait_for_listener(py_pid, 8080)
    wait_for_listener(socat_pid, 8443)


def test_tls_port_forwarding():
    _, py_pid, socat_pid = read_run_log()
    wait_for_listener(py_pid, 8080)
    wait_for_listener(socat_pid, 8443)

    with urllib.request.urlopen("http://localhost:8080/config.json", timeout=5) as response:
        direct = response.read().decode("utf-8")
    assert json.loads(direct) == {"device_id": "Gateway-Alpha", "sensor": "Humidity"}

    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    url = "https://localhost:8443/config.json"
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, context=ctx, timeout=5) as response:
            body = response.read().decode("utf-8")
            data = json.loads(body)
            assert data.get("device_id") == "Gateway-Alpha", "device_id fetched via TLS does not match."
            assert data.get("sensor") == "Humidity", "sensor fetched via TLS does not match."
    except Exception as e:
        pytest.fail(f"Failed to fetch {url} via TLS: {e}")

    with socket.create_connection(("localhost", 8443), timeout=5) as raw:
        with ctx.wrap_socket(raw, server_hostname="localhost") as tls_sock:
            served_der = tls_sock.getpeercert(binary_form=True)
    expected_der = subprocess.run(
        ["openssl", "x509", "-in", "/home/user/certs/edge.crt", "-outform", "DER"],
        check=True, stdout=subprocess.PIPE
    ).stdout
    assert served_der == expected_der, "Port 8443 is not serving the required edge.crt certificate."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
