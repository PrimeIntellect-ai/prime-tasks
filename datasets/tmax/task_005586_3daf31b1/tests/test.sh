#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import socket
import stat
import subprocess
import time
import urllib.error
import urllib.request
import uuid
import pytest

NGINX_CONF = "/home/user/nginx/conf/nginx.conf"
SOCKET_PATH = "/home/user/run/app.sock"


def cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return f.read().replace(b"\0", b" ").decode(errors="replace").strip()
    except OSError:
        return ""


def exe_name(pid):
    try:
        return os.path.basename(os.readlink(f"/proc/{pid}/exe"))
    except OSError:
        return ""


def ppid(pid):
    try:
        with open(f"/proc/{pid}/status") as f:
            for line in f:
                if line.startswith("PPid:"):
                    return int(line.split()[1])
    except OSError:
        pass
    return 0


def ancestors(pid):
    result = []
    seen = set()
    while pid > 1 and pid not in seen:
        seen.add(pid)
        result.append(pid)
        pid = ppid(pid)
    return result


def owners_of_inodes(inodes):
    owners = set()
    if not inodes:
        return owners
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            fds = os.listdir(fd_dir)
        except OSError:
            continue
        for fd in fds:
            try:
                target = os.readlink(f"{fd_dir}/{fd}")
            except OSError:
                continue
            match = re.fullmatch(r"socket:\[(\d+)\]", target)
            if match and match.group(1) in inodes:
                owners.add(int(entry))
                break
    return owners


def tcp_listener_owners(port):
    inodes = set()
    wanted_port = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[3] == "0A":
                        local_port = fields[1].rsplit(":", 1)[1].upper()
                        if local_port == wanted_port:
                            inodes.add(fields[9])
        except OSError:
            pass
    return owners_of_inodes(inodes)


def unix_socket_owners(path):
    inodes = set()
    with open("/proc/net/unix") as f:
        next(f, None)
        for line in f:
            fields = line.split()
            if len(fields) >= 8 and fields[-1] == path:
                inodes.add(fields[6])
    return owners_of_inodes(inodes)


def real_backend_owner():
    owners = unix_socket_owners(SOCKET_PATH)
    valid = []
    for pid in owners:
        command = cmdline(pid)
        if exe_name(pid) == "socat" and f"UNIX-LISTEN:{SOCKET_PATH}" in command and "EXEC:/home/user/app.sh" in command:
            valid.append(pid)
    return valid


def http_status(user_agent=None, path="/", timeout=4):
    request = urllib.request.Request(f"http://127.0.0.1:8080{path}")
    if user_agent is not None:
        request.add_header("User-Agent", user_agent)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return response.status
    except urllib.error.HTTPError as error:
        return error.code


def unix_request(user_agent):
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(4)
    client.connect(SOCKET_PATH)
    request = (
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        f"HTTP_USER_AGENT: {user_agent}\r\n"
        "Connection: close\r\n\r\n"
    ).encode()
    client.sendall(request)
    client.shutdown(socket.SHUT_WR)
    chunks = []
    while True:
        data = client.recv(4096)
        if not data:
            break
        chunks.append(data)
    client.close()
    return b"".join(chunks)


def test_nginx_config_and_process():
    """Verify Nginx config points to the correct socket and Nginx is running."""
    assert os.path.isfile(NGINX_CONF), f"File {NGINX_CONF} is missing."
    with open(NGINX_CONF) as f:
        content = f.read()
    assert "proxy_pass http://unix:/home/user/run/app.sock;" in content, "Nginx config does not point to the correct socket path."

    try:
        subprocess.check_output(["pgrep", "-f", "nginx: master process"])
    except subprocess.CalledProcessError:
        pytest.fail("Nginx master process is not running.")

    checked = subprocess.run(
        ["nginx", "-t", "-p", "/home/user/nginx", "-c", "conf/nginx.conf"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    assert checked.returncode == 0, checked.stderr

    owners = tcp_listener_owners(8080)
    assert owners, "Nothing owns the listening TCP socket on port 8080."
    assert all(exe_name(pid) == "nginx" for pid in owners), "Port 8080 is owned by a non-Nginx server."
    related = {ancestor for pid in owners for ancestor in ancestors(pid)}
    assert any(
        exe_name(pid) == "nginx"
        and "-p /home/user/nginx" in cmdline(pid)
        and "-c conf/nginx.conf" in cmdline(pid)
        for pid in related
    ), "The listener on port 8080 is not the configured Nginx instance."


def test_run_directory_permissions():
    """Verify /home/user/run/ directory exists and has 777 permissions."""
    run_dir = "/home/user/run"
    assert os.path.isdir(run_dir), f"Directory {run_dir} is missing."
    perms = stat.S_IMODE(os.stat(run_dir).st_mode)
    assert perms == 0o777, f"Permissions for {run_dir} are {oct(perms)}, expected 0o777."


def test_app_sh_robustness():
    """Verify app.sh does not use exit 1 and really returns 403 cleanly."""
    app_path = "/home/user/app.sh"
    assert os.path.isfile(app_path), f"File {app_path} is missing."
    with open(app_path) as f:
        content = f.read()
    assert "exit 1" not in content, "app.sh still contains the fragile 'exit 1' logic."
    assert "403" in content, "app.sh does not contain a 403 Forbidden response."

    normal = subprocess.run(
        [app_path], input="GET / HTTP/1.1\r\nHTTP_USER_AGENT: NormalClient\r\n\r\n",
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=4
    )
    assert normal.returncode == 0
    assert normal.stdout.startswith("HTTP/1.1 200"), normal.stdout

    bad = subprocess.run(
        [app_path], input="GET / HTTP/1.1\r\nHTTP_USER_AGENT: BadBot-random\r\n\r\n",
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=4
    )
    assert bad.returncode == 0, "app.sh did not exit cleanly for BadBot."
    assert bad.stdout.startswith("HTTP/1.1 403 Forbidden"), bad.stdout


def test_supervisor_exists():
    """Verify supervisor.sh exists and includes the required restart delay."""
    supervisor_path = "/home/user/supervisor.sh"
    assert os.path.isfile(supervisor_path), f"File {supervisor_path} is missing."
    with open(supervisor_path) as f:
        content = f.read()
    assert "/home/user/daemon.sh" in content, "supervisor.sh does not run daemon.sh."
    assert re.search(r"(^|[;&|[:space:]])sleep[[:space:]]+1([[:space:];&]|$)", content, re.MULTILINE), "supervisor.sh does not sleep for 1 second between restarts."


def test_actual_nginx_unix_socket_chain():
    """Prove that configured Nginx and the real socat UNIX listener carry requests."""
    assert os.path.exists(SOCKET_PATH), "Backend socket is missing."
    assert stat.S_ISSOCK(os.stat(SOCKET_PATH).st_mode), "app.sock is not a UNIX socket."
    backend_pids = real_backend_owner()
    assert backend_pids, "The UNIX socket is not owned by the required socat listener."

    # Exercise the backend directly through the UNIX socket with derived inputs.
    good_ua = "VerifierGood-" + uuid.uuid4().hex
    bad_ua = "Verifier-BadBot-" + uuid.uuid4().hex
    assert unix_request(good_ua).startswith(b"HTTP/1.1 200")
    assert unix_request(bad_ua).startswith(b"HTTP/1.1 403 Forbidden")

    # A unique proxied request must be recorded by this Nginx instance.
    token = "verifier-" + uuid.uuid4().hex
    assert http_status(path=f"/{token}") == 200
    access_log = "/home/user/nginx/logs/access.log"
    assert os.path.isfile(access_log)
    with open(access_log, errors="replace") as f:
        assert token in f.read(), "The request was not handled by the configured Nginx access log."

    # Removing the configured pathname must break the HTTP upstream. This rules
    # out an unrelated HTTP service returning the expected status codes.
    held = SOCKET_PATH + ".verifier-held"
    if os.path.lexists(held):
        os.unlink(held)
    os.rename(SOCKET_PATH, held)
    try:
        assert http_status(path="/missing-upstream-" + uuid.uuid4().hex) == 502, "Port 8080 did not depend on the configured UNIX socket."
    finally:
        if os.path.lexists(held):
            if os.path.lexists(SOCKET_PATH):
                os.unlink(SOCKET_PATH)
            os.rename(held, SOCKET_PATH)
    assert http_status(path="/restored-" + uuid.uuid4().hex) == 200


def test_http_responses():
    """Verify the server returns 200 for normal requests and 403 for BadBot."""
    req = urllib.request.Request("http://127.0.0.1:8080/")
    try:
        with urllib.request.urlopen(req, timeout=4) as response:
            assert response.status == 200, f"Expected 200 OK, got {response.status}"
    except urllib.error.HTTPError as e:
        pytest.fail(f"Normal request failed with HTTP error {e.code}")
    except urllib.error.URLError as e:
        pytest.fail(f"Normal request failed to connect: {e.reason}")

    req_bot = urllib.request.Request("http://127.0.0.1:8080/")
    req_bot.add_header("User-Agent", "BadBot")
    try:
        with urllib.request.urlopen(req_bot, timeout=4) as response:
            pytest.fail(f"Expected 403 Forbidden, but got {response.status}")
    except urllib.error.HTTPError as e:
        assert e.code == 403, f"Expected 403 Forbidden, got {e.code}"
    except urllib.error.URLError as e:
        pytest.fail(f"BadBot request failed to connect: {e.reason}")


def test_supervisor_restarts_daemon():
    """Verify a running supervisor actually restarts the socket-owning daemon."""
    try:
        subprocess.check_output(["pgrep", "-f", "socat UNIX-LISTEN:/home/user/run/app.sock"])
    except subprocess.CalledProcessError:
        pytest.fail("Socat daemon is not running initially.")

    old = real_backend_owner()
    assert old, "No real socat listener owns app.sock initially."
    subprocess.call(["pkill", "-f", "socat"])
    time.sleep(3)

    try:
        subprocess.check_output(["pgrep", "-f", "socat UNIX-LISTEN:/home/user/run/app.sock"])
    except subprocess.CalledProcessError:
        pytest.fail("Supervisor failed to restart the daemon after it was killed.")

    new = real_backend_owner()
    assert new, "Supervisor did not recreate a real socat UNIX listener."
    assert not set(old).intersection(new), "The original daemon was not replaced."
    assert any(
        any("/home/user/supervisor.sh" in cmdline(parent) for parent in ancestors(pid)[1:])
        for pid in new
    ), "The restarted daemon is not a child of the running supervisor.sh."
    assert http_status(path="/after-restart-" + uuid.uuid4().hex) == 200


def test_results_log():
    """Execute verify.sh and require it to produce exactly the requested codes."""
    verify_path = "/home/user/verify.sh"
    log_path = "/home/user/results.log"
    assert os.path.isfile(verify_path), f"File {verify_path} is missing."
    if os.path.lexists(log_path):
        os.unlink(log_path)
    result = subprocess.run(
        ["/bin/bash", verify_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=15
    )
    assert result.returncode == 0, f"verify.sh failed: {result.stderr}"
    assert os.path.isfile(log_path), f"File {log_path} is missing."
    with open(log_path) as f:
        content = f.read()
    assert "200" in content, "results.log does not contain 200 status code."
    assert "403" in content, "results.log does not contain 403 status code."
    assert content.splitlines() == ["200", "403"], "results.log must contain one exact status code per line."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
