#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import signal
import socket
import ssl
import subprocess
import time
import urllib.request
from pathlib import Path

import pytest


def listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) >= 10 and fields[3] == "0A":
                if int(fields[1].split(":")[1], 16) == port:
                    inodes.add(fields[9])

    pids = set()
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / "fd").iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    pids.add(int(proc.name))
                    break
        except OSError:
            continue
    return pids


def read_pid():
    pid_path = "/home/user/server.pid"
    assert os.path.isfile(pid_path), f"PID file {pid_path} does not exist."
    with open(pid_path, "r") as f:
        pid_str = f.read().strip()
    assert pid_str.isdigit(), f"PID file {pid_path} does not contain a valid integer."
    return int(pid_str)


def https_get(path):
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    url = f"https://localhost:8443/{path}"
    with urllib.request.urlopen(url, context=ctx, timeout=5) as response:
        return response.status, response.read()


def test_symlinks_created():
    """Verify that the directory structure and symlinks are properly created."""
    links = [
        ("2023/01", "cost_report_2023_01.html"),
        ("2023/02", "cost_report_2023_02.html"),
        ("2024/03", "cost_report_2024_03.html"),
    ]

    for path_part, target_file in links:
        link_path = f"/home/user/finops_web/{path_part}/index.html"
        assert os.path.islink(link_path), f"Expected symlink at {link_path} is missing or not a symlink."

        target = os.readlink(link_path)
        abs_target = os.path.normpath(os.path.join(os.path.dirname(link_path), target))
        expected_target = f"/home/user/raw_reports/{target_file}"
        assert abs_target == expected_target, f"Symlink {link_path} points to {abs_target}, expected {expected_target}."


def test_expect_script_exists():
    """Verify the expect script was created."""
    script_path = "/home/user/gen_cert.exp"
    assert os.path.isfile(script_path), f"Expect script {script_path} does not exist."


def test_tls_certificate_details():
    """Verify the TLS certificate exists and has the correct subject details."""
    cert_path = "/home/user/cert.pem"
    key_path = "/home/user/key.pem"

    assert os.path.isfile(cert_path), f"Certificate file {cert_path} does not exist."
    assert os.path.isfile(key_path), f"Key file {key_path} does not exist."

    result = subprocess.run(["openssl", "x509", "-in", cert_path, "-noout", "-subject"], capture_output=True, text=True)
    assert result.returncode == 0, "Failed to read certificate subject."

    subject = result.stdout
    expected_parts = [
        "C = US",
        "ST = California",
        "L = San Francisco",
        "O = CloudCo",
        "OU = FinOps",
        "CN = localhost",
        "emailAddress = admin@cloudco.local"
    ]

    for part in expected_parts:
        assert part in subject, f"Expected '{part}' in certificate subject, but got: {subject}"


def test_expect_script_actually_generates_certificate_interactively():
    script_path = Path("/home/user/gen_cert.exp")
    source = script_path.read_text(errors="replace")
    active_source = "\n".join(line for line in source.splitlines() if not line.lstrip().startswith("#"))
    assert re.search(r"(?m)^\s*expect\b", active_source), "gen_cert.exp does not use expect to handle prompts."
    assert re.search(r"(?m)^\s*send(?:_user)?\b", active_source), "gen_cert.exp does not send interactive answers."
    for value in ("US", "California", "San Francisco", "CloudCo", "FinOps", "localhost", "admin@cloudco.local"):
        assert value in active_source, f"gen_cert.exp does not contain the required answer {value!r}."
    assert not re.search(r"(^|\s)-(?:subj|batch)(?:\s|$)", active_source), "Forbidden -subj or batch mode found in gen_cert.exp."

    wrapper_dir = Path("/tmp/openssl-verifier-wrapper")
    wrapper_dir.mkdir(exist_ok=True)
    log_path = wrapper_dir / "calls.log"
    log_path.write_text("")
    wrapper = wrapper_dir / "openssl"
    wrapper.write_text("""#!/bin/bash
log=/tmp/openssl-verifier-wrapper/calls.log
expected=(req -x509 -newkey rsa:2048 -nodes -keyout /home/user/key.pem -out /home/user/cert.pem -days 365)
if [ \"$#\" -eq \"${#expected[@]}\" ]; then
  ok=1
  for ((i=0; i<$#; i++)); do
    [ \"${!((i+1))}\" = \"${expected[$i]}\" ] || ok=0
  done
else
  ok=0
fi
# The indirect expansion above is not portable across all bash versions; verify again using arrays.
actual=(\"$@\")
ok=1
[ \"${#actual[@]}\" -eq \"${#expected[@]}\" ] || ok=0
for ((i=0; i<${#expected[@]} && i<${#actual[@]}; i++)); do
  [ \"${actual[$i]}\" = \"${expected[$i]}\" ] || ok=0
done
if [ \"$ok\" -eq 1 ]; then echo EXACT >> \"$log\"; else printf 'BAD %q ' \"$@\" >> \"$log\"; echo >> \"$log\"; fi
exec /usr/bin/openssl \"$@\"
""")
    wrapper.chmod(0o755)

    for output in ("/home/user/cert.pem", "/home/user/key.pem"):
        try:
            os.unlink(output)
        except FileNotFoundError:
            pass

    started = time.time()
    env = os.environ.copy()
    env["PATH"] = str(wrapper_dir) + os.pathsep + env.get("PATH", "")
    result = subprocess.run(["expect", str(script_path)], env=env, capture_output=True, text=True, timeout=45)
    assert result.returncode == 0, f"gen_cert.exp failed when executed:\n{result.stdout}\n{result.stderr}"
    calls = log_path.read_text().splitlines()
    assert calls and all(call == "EXACT" for call in calls), "The expect script did not invoke exactly the required openssl command."

    cert = Path("/home/user/cert.pem")
    key = Path("/home/user/key.pem")
    assert cert.is_file() and key.is_file(), "Executing gen_cert.exp did not create cert.pem and key.pem."
    assert cert.stat().st_mtime >= started and key.stat().st_mtime >= started, "Certificate outputs were not freshly generated."

    cert_pub = subprocess.run(["openssl", "x509", "-in", str(cert), "-pubkey", "-noout"], capture_output=True, check=True).stdout
    key_pub = subprocess.run(["openssl", "pkey", "-in", str(key), "-pubout"], capture_output=True, check=True).stdout
    assert cert_pub == key_pub, "cert.pem and key.pem do not form a matching key pair."

    details = subprocess.run(["openssl", "x509", "-in", str(cert), "-noout", "-subject", "-text"], capture_output=True, text=True, check=True).stdout
    for part in ("C = US", "ST = California", "L = San Francisco", "O = CloudCo", "OU = FinOps", "CN = localhost", "emailAddress = admin@cloudco.local"):
        assert part in details, f"Freshly generated certificate is missing {part!r}."
    assert "Public-Key: (2048 bit)" in details, "Freshly generated certificate does not use a 2048-bit RSA key."


def test_server_script_and_pid():
    """Verify the start_server.sh script exists and the server PID is recorded and running."""
    script_path = "/home/user/start_server.sh"
    assert os.path.isfile(script_path), f"Server script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Server script {script_path} is not executable."

    pid = read_pid()
    try:
        os.kill(pid, 0)
    except OSError:
        pytest.fail(f"Process with PID {pid} is not running.")
    assert pid in listener_pids(8443), f"PID {pid} is not the web server listening on port 8443."


def test_start_server_script_can_launch_server():
    old_pid = read_pid()
    assert old_pid > 1 and old_pid in listener_pids(8443), "The recorded PID is not the current HTTPS listener."
    os.kill(old_pid, signal.SIGTERM)
    deadline = time.time() + 5
    while time.time() < deadline and listener_pids(8443):
        time.sleep(0.1)
    if listener_pids(8443):
        os.kill(old_pid, signal.SIGKILL)
        time.sleep(0.5)
    assert not listener_pids(8443), "Could not stop the original server to test start_server.sh."

    launched = time.time()
    result = subprocess.run(["/home/user/start_server.sh"], cwd="/home/user", capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, f"start_server.sh failed:\n{result.stdout}\n{result.stderr}"
    assert os.path.getmtime("/home/user/server.pid") >= launched, "start_server.sh did not update server.pid."

    deadline = time.time() + 8
    new_pid = None
    while time.time() < deadline:
        try:
            new_pid = read_pid()
            if new_pid in listener_pids(8443):
                break
        except AssertionError:
            pass
        time.sleep(0.1)
    assert new_pid is not None and new_pid in listener_pids(8443), "start_server.sh did not start the recorded PID on port 8443."
    assert new_pid != old_pid, "start_server.sh did not start a new server process."


def test_https_server_reachable_and_serves_finops_root():
    """Verify HTTPS serves all reports and arbitrary content from finops_web."""
    expected = {
        "2023/01/index.html": b"<html>Report Jan 2023</html>",
        "2023/02/index.html": b"<html>Report Feb 2023</html>",
        "2024/03/index.html": b"<html>Report Mar 2024</html>",
    }
    for path, wanted in expected.items():
        try:
            status, content = https_get(path)
        except Exception as e:
            pytest.fail(f"Failed to fetch https://localhost:8443/{path}: {e}")
        assert status == 200, f"Expected HTTP 200 for {path}, got {status}"
        assert wanted in content, f"Server returned incorrect content for {path}."

    marker_name = f"verifier-{os.urandom(12).hex()}.txt"
    marker_data = os.urandom(48).hex().encode()
    marker_path = Path("/home/user/finops_web") / marker_name
    marker_path.write_bytes(marker_data)
    try:
        status, content = https_get(marker_name)
        assert status == 200 and content == marker_data, "Server is not generally serving /home/user/finops_web/."
    finally:
        marker_path.unlink(missing_ok=True)

    expected_der = ssl.PEM_cert_to_DER_cert(Path("/home/user/cert.pem").read_text())
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    with socket.create_connection(("localhost", 8443), timeout=5) as raw:
        with ctx.wrap_socket(raw, server_hostname="localhost") as tls:
            served_der = tls.getpeercert(binary_form=True)
    assert served_der == expected_der, "HTTPS server is not using /home/user/cert.pem."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
