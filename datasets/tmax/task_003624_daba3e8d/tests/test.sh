#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import re
import signal
import socket
import subprocess
import tempfile
import time
import urllib.request
import pytest

USER_UID = pwd.getpwnam("user").pw_uid
USER_GID = pwd.getpwnam("user").pw_gid
OPERATOR = "/home/user/operator"
SOURCE = "/home/user/operator.c"


def listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local, state, inode = fields[1], fields[3], fields[9]
                    if state != "0A":
                        continue
                    _, hex_port = local.rsplit(":", 1)
                    if int(hex_port, 16) == port:
                        inodes.add(inode)
        except FileNotFoundError:
            pass

    pids = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    pids.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return pids


def raw_http(port):
    with socket.create_connection(("127.0.0.1", port), timeout=3) as sock:
        sock.settimeout(3)
        sock.sendall(b"GET /sync HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n")
        chunks = []
        while True:
            data = sock.recv(4096)
            if not data:
                break
            chunks.append(data)
    return b"".join(chunks)


def start_as_user(argv):
    def demote():
        os.setgroups([])
        os.setgid(USER_GID)
        os.setuid(USER_UID)
    return subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL, preexec_fn=demote)


def wait_listening(port, timeout=4):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.15):
                return
        except OSError:
            time.sleep(0.05)
    pytest.fail(f"Port {port} did not begin listening")


def test_cicd_script_exists_and_executable():
    script_path = "/home/user/cicd.sh"
    assert os.path.isfile(script_path), f"FAIL: {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"FAIL: {script_path} is not executable."


def test_operator_artifacts_and_source_build():
    assert os.path.isfile(SOURCE), f"FAIL: {SOURCE} does not exist."
    assert os.path.isfile(OPERATOR), f"FAIL: {OPERATOR} does not exist."
    assert os.access(OPERATOR, os.X_OK), f"FAIL: {OPERATOR} is not executable."
    with open(OPERATOR, "rb") as f:
        assert f.read(4) == b"\x7fELF", "FAIL: operator is not a compiled ELF executable."

    rebuilt = "/tmp/operator_from_source"
    result = subprocess.run(["gcc", SOURCE, "-o", rebuilt], capture_output=True, text=True)
    assert result.returncode == 0, f"FAIL: operator.c does not compile: {result.stderr}"

    with socket.socket() as reserve:
        reserve.bind(("127.0.0.1", 0))
        port = reserve.getsockname()[1]
    proc = start_as_user([rebuilt, str(port)])
    try:
        wait_listening(port)
        name = f"source_build_{os.urandom(6).hex()}.yaml"
        with open(f"/home/user/manifests/{name}", "w") as f:
            f.write("test")
        response = raw_http(port)
        assert response == b"HTTP/1.1 200 OK\r\n\r\nOK\n"
        with open(f"/home/user/mail_spool/{name}.processed") as f:
            assert f.read() == f"Processed {name}"
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()


def test_haproxy_running_and_listening():
    try:
        output = subprocess.check_output(["pgrep", "-x", "haproxy"]).decode()
        assert output.strip() != "", "FAIL: HAProxy is not running."
    except subprocess.CalledProcessError:
        pytest.fail("FAIL: HAProxy is not running.")

    try:
        output = subprocess.check_output(["ss", "-tuln"]).decode()
        assert ":8080" in output, "FAIL: Port 8080 is not listening."
    except subprocess.CalledProcessError:
        pytest.fail("FAIL: Failed to check listening ports.")

    pids = listener_pids(8080)
    assert pids, "FAIL: No process owns the listener on port 8080."
    assert any(os.path.basename(os.readlink(f"/proc/{pid}/exe")) == "haproxy" for pid in pids), \
        "FAIL: The port 8080 listener is not HAProxy."


def test_haproxy_configuration():
    cfg = "/home/user/haproxy.cfg"
    assert os.path.isfile(cfg), f"FAIL: {cfg} does not exist."
    checked = subprocess.run(["haproxy", "-c", "-f", cfg], capture_output=True, text=True)
    assert checked.returncode == 0, f"FAIL: Invalid HAProxy configuration: {checked.stderr}"
    with open(cfg) as f:
        text = re.sub(r"#.*", "", f.read(), flags=re.MULTILINE)
    assert re.search(r"(?im)^\s*frontend\s+\S+", text), "FAIL: HAProxy frontend is missing."
    assert re.search(r"(?im)^\s*bind\s+127\.0\.0\.1:8080(?:\s|$)", text), \
        "FAIL: HAProxy does not bind its frontend to 127.0.0.1:8080."
    assert re.search(r"(?im)^\s*backend\s+\S+", text), "FAIL: HAProxy backend is missing."
    assert re.search(r"(?im)^\s*balance\s+roundrobin(?:\s|$)", text), \
        "FAIL: HAProxy backend is not configured for round-robin balancing."
    assert re.search(r"(?im)^\s*server\s+\S+\s+127\.0\.0\.1:8081(?:\s|$)", text), \
        "FAIL: Backend 127.0.0.1:8081 is missing."
    assert re.search(r"(?im)^\s*server\s+\S+\s+127\.0\.0\.1:8082(?:\s|$)", text), \
        "FAIL: Backend 127.0.0.1:8082 is missing."


def test_operator_listening():
    try:
        output = subprocess.check_output(["ss", "-tuln"]).decode()
        assert ":8081" in output, "FAIL: Port 8081 is not listening."
        assert ":8082" in output, "FAIL: Port 8082 is not listening."
    except subprocess.CalledProcessError:
        pytest.fail("FAIL: Failed to check listening ports.")

    for port in (8081, 8082):
        pids = listener_pids(port)
        assert len(pids) == 1, f"FAIL: Expected one operator listener on port {port}, got {pids}."
        pid = next(iter(pids))
        assert os.path.realpath(f"/proc/{pid}/exe") == OPERATOR, \
            f"FAIL: Listener on port {port} is not {OPERATOR}."
        assert os.stat(f"/proc/{pid}").st_uid == USER_UID, \
            f"FAIL: Operator on port {port} is not running as the default user."


def test_cicd_execution_and_operator_logic():
    script_path = "/home/user/cicd.sh"
    processed_file = "/home/user/mail_spool/deployment.yaml.processed"
    nonce = os.urandom(8).hex()
    extra_name = f"cicd_probe_{nonce}.yaml"
    extra_manifest = f"/home/user/manifests/{extra_name}"
    extra_processed = f"/home/user/mail_spool/{extra_name}.processed"

    with open(extra_manifest, "w") as f:
        f.write("probe")
    with open(extra_processed, "w") as f:
        f.write("stale")
    if os.path.exists(processed_file):
        os.remove(processed_file)

    try:
        subprocess.run(["bash", script_path], check=True, timeout=5)
    except subprocess.CalledProcessError:
        pytest.fail(f"FAIL: Execution of {script_path} failed.")
    except subprocess.TimeoutExpired:
        pytest.fail(f"FAIL: Execution of {script_path} timed out.")

    time.sleep(1)
    assert os.path.isfile(processed_file), f"FAIL: Processed file {processed_file} not found after running cicd.sh."
    with open(processed_file) as f:
        content = f.read().strip()
    expected_content = "Processed deployment.yaml"
    assert content == expected_content, \
        f"FAIL: Incorrect content in processed file. Expected '{expected_content}', got '{content}'."
    with open("/home/user/manifests/deployment.yaml") as f:
        assert f.read() == "kind: Deployment", "FAIL: cicd.sh did not create the required deployment manifest."
    with open(extra_processed) as f:
        assert f.read() == f"Processed {extra_name}", \
            "FAIL: cicd.sh did not trigger a real sync through the running infrastructure."


def test_operator_direct_http_response():
    dummy_manifest = "/home/user/manifests/dummy.yaml"
    with open(dummy_manifest, "w") as f:
        f.write("dummy")
    try:
        req = urllib.request.Request("http://127.0.0.1:8081/sync")
        with urllib.request.urlopen(req, timeout=2) as response:
            body = response.read().decode()
            assert "OK" in body, "FAIL: Operator on port 8081 did not return OK."
    except Exception as e:
        pytest.fail(f"FAIL: Direct request to operator on port 8081 failed: {e}")
    with open("/home/user/mail_spool/dummy.yaml.processed") as f:
        assert f.read() == "Processed dummy.yaml", "FAIL: dummy.yaml was not processed."


def test_every_yaml_overwrite_and_exact_response_on_both_instances():
    nonce = os.urandom(8).hex()
    yaml_names = [f"alpha_{nonce}.yaml", f"name.with.dots_{nonce}.yaml"]
    ignored_name = f"ignored_{nonce}.yml"
    with open(f"/home/user/manifests/{ignored_name}", "w") as f:
        f.write("ignore")
    ignored_processed = f"/home/user/mail_spool/{ignored_name}.processed"
    if os.path.exists(ignored_processed):
        os.remove(ignored_processed)

    for name in yaml_names:
        with open(f"/home/user/manifests/{name}", "w") as f:
            f.write("manifest")
        with open(f"/home/user/mail_spool/{name}.processed", "w") as f:
            f.write("stale content that must be overwritten")

    for port in (8081, 8082):
        assert raw_http(port) == b"HTTP/1.1 200 OK\r\n\r\nOK\n", \
            f"FAIL: Operator on port {port} did not return the required exact HTTP response."
        for name in yaml_names:
            with open(f"/home/user/mail_spool/{name}.processed") as f:
                assert f.read() == f"Processed {name}"
    assert not os.path.exists(ignored_processed), "FAIL: A non-.yaml file was processed."


def test_haproxy_actually_round_robins_between_both_backends():
    original_pids = set()
    for port in (8081, 8082):
        original_pids.update(listener_pids(port))
    assert len(original_pids) == 2, "FAIL: Could not identify both operator instances."

    probe_source = r'''
import socket, sys
port = int(sys.argv[1]); marker = sys.argv[2].encode()
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", port)); s.listen(20)
while True:
    c, _ = s.accept()
    try:
        c.settimeout(1)
        data = b""
        while b"\r\n\r\n" not in data:
            part = c.recv(4096)
            if not part: break
            data += part
        c.sendall(b"HTTP/1.1 200 OK\r\nContent-Length: 1\r\nConnection: close\r\n\r\n" + marker)
    finally:
        c.close()
'''
    probe_path = "/tmp/backend_probe.py"
    with open(probe_path, "w") as f:
        f.write(probe_source)

    probes = []
    try:
        for pid in original_pids:
            os.kill(pid, signal.SIGTERM)
        deadline = time.time() + 3
        while time.time() < deadline and any(os.path.exists(f"/proc/{pid}") for pid in original_pids):
            time.sleep(0.05)
        for pid in original_pids:
            if os.path.exists(f"/proc/{pid}"):
                os.kill(pid, signal.SIGKILL)
        time.sleep(0.2)

        probes = [subprocess.Popen(["python3", probe_path, "8081", "A"]),
                  subprocess.Popen(["python3", probe_path, "8082", "B"])]
        wait_listening(8081)
        wait_listening(8082)
        bodies = []
        for _ in range(6):
            req = urllib.request.Request("http://127.0.0.1:8080/sync", headers={"Connection": "close"})
            with urllib.request.urlopen(req, timeout=3) as response:
                bodies.append(response.read().decode())
        assert set(bodies) == {"A", "B"}, \
            f"FAIL: HAProxy did not route requests to both backends; observed {bodies}."
        assert all(bodies[i] != bodies[i + 1] for i in range(len(bodies) - 1)), \
            f"FAIL: HAProxy did not round-robin between the backends; observed {bodies}."
    finally:
        for proc in probes:
            proc.terminate()
        for proc in probes:
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
        time.sleep(0.2)
        replacements = [start_as_user([OPERATOR, "8081"]), start_as_user([OPERATOR, "8082"])]
        wait_listening(8081)
        wait_listening(8082)

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
