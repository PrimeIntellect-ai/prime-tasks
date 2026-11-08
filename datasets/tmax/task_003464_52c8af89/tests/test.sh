#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import socket
import stat
import subprocess
import time
import uuid

import pytest
import requests

REPO = "/home/user/monitor.git"
DEPLOY = "/home/user/deploy"
QMP_SOCKET = "/tmp/legacy_qmp.sock"
MONITOR = "/app/legacy_monitor"


def run(cmd, **kwargs):
    kwargs.setdefault("text", True)
    kwargs.setdefault("timeout", 20)
    return subprocess.run(cmd, check=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, **kwargs)


def listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[3] == "0A":
                        if int(fields[1].rsplit(":", 1)[1], 16) == port:
                            inodes.add(fields[9])
        except FileNotFoundError:
            pass

    owners = set()
    for proc in os.listdir("/proc"):
        if not proc.isdigit():
            continue
        fd_dir = f"/proc/{proc}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    owners.add(int(proc))
        except (FileNotFoundError, PermissionError):
            continue
    return owners


def recv_all(sock):
    chunks = []
    while True:
        data = sock.recv(4096)
        if not data:
            return b"".join(chunks)
        chunks.append(data)


def qmp_command(stream, command):
    stream.write((json.dumps({"execute": command}) + "\r\n").encode())
    stream.flush()
    deadline = time.time() + 5
    while time.time() < deadline:
        line = stream.readline()
        assert line, "QMP connection closed unexpectedly"
        message = json.loads(line)
        if "error" in message:
            pytest.fail(f"QMP command {command} failed: {message['error']}")
        if "return" in message:
            return message["return"]
    pytest.fail(f"No QMP response to {command}")


def test_git_setup_and_push_deployment():
    hook_path = os.path.join(REPO, "hooks/post-receive")
    assert os.path.isdir(REPO), f"Bare git repository not found at {REPO}"
    assert os.path.isdir(DEPLOY), f"Deploy directory not found at {DEPLOY}"
    assert os.path.exists(hook_path), f"post-receive hook not found at {hook_path}"
    assert os.access(hook_path, os.X_OK), "post-receive hook is not executable"
    assert run(["git", "--git-dir", REPO, "rev-parse", "--is-bare-repository"]).stdout.strip() == "true"

    old_8040 = listener_pids(8040)
    old_8080 = listener_pids(8080)
    assert old_8040, "No daemon is listening on TCP port 8040 before the push"
    assert old_8080, "No daemon is listening on TCP port 8080 before the push"

    work = f"/tmp/verify-clone-{uuid.uuid4().hex}"
    marker_id = uuid.uuid4().hex
    marker = f"/tmp/hook-started-{marker_id}"
    try:
        run(["git", "clone", REPO, work])
        run(["git", "-C", work, "config", "user.email", "verifier@example.invalid"])
        run(["git", "-C", work, "config", "user.name", "Verifier"])
        branch = run(["git", "-C", work, "symbolic-ref", "--short", "HEAD"]).stdout.strip()
        tracked = run(["git", "-C", work, "ls-files", "*.c"]).stdout.splitlines()
        assert tracked, "The pushed repository does not contain tracked C source code"

        source = os.path.join(work, tracked[0])
        with open(source, "a") as f:
            f.write("\n#include <stdio.h>\n")
            f.write("__attribute__((constructor)) static void verifier_push_marker(void) {\n")
            f.write(f'  FILE *f = fopen("{marker}", "w");\n')
            f.write(f'  if (f) {{ fputs("{marker_id}", f); fclose(f); }}\n')
            f.write("}\n")

        run(["git", "-C", work, "add", "--", tracked[0]])
        run(["git", "-C", work, "commit", "-m", f"verification update {marker_id}"])
        pushed_commit = run(["git", "-C", work, "rev-parse", "HEAD"]).stdout.strip()
        run(["git", "-C", work, "push", "origin", f"HEAD:refs/heads/{branch}"], timeout=30)
        assert run(["git", "--git-dir", REPO, "rev-parse", f"refs/heads/{branch}"]).stdout.strip() == pushed_commit

        deadline = time.time() + 15
        new_8040 = set()
        new_8080 = set()
        while time.time() < deadline:
            new_8040 = listener_pids(8040)
            new_8080 = listener_pids(8080)
            if os.path.exists(marker) and new_8040 and new_8080 and \
                    old_8040.isdisjoint(new_8040) and old_8080.isdisjoint(new_8080):
                break
            time.sleep(0.25)

        assert os.path.exists(marker), "Pushed C update was not compiled and started by post-receive"
        assert open(marker).read() == marker_id
        deployed_source = os.path.join(DEPLOY, tracked[0])
        assert os.path.isfile(deployed_source), "Latest pushed source was not checked out to the deploy directory"
        assert marker_id in open(deployed_source, errors="replace").read()
        assert new_8040 and old_8040.isdisjoint(new_8040), "Raw TCP daemon was not restarted after push"
        assert new_8080 and old_8080.isdisjoint(new_8080), "HTTP daemon was not restarted after push"
    finally:
        shutil.rmtree(work, ignore_errors=True)
        try:
            os.unlink(marker)
        except FileNotFoundError:
            pass


def test_qemu_qmp_socket():
    assert os.path.exists(QMP_SOCKET), f"QMP socket not found at {QMP_SOCKET}. Is QEMU running?"
    mode = os.stat(QMP_SOCKET).st_mode
    assert stat.S_ISSOCK(mode), f"Path {QMP_SOCKET} is not a socket"

    qemu_pids = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            raw = open(f"/proc/{entry}/cmdline", "rb").read()
        except (FileNotFoundError, PermissionError):
            continue
        argv = [x.decode(errors="replace") for x in raw.split(b"\0") if x]
        if not argv or "qemu-system-x86_64" not in os.path.basename(argv[0]):
            continue
        if "/app/legacy_vm.qcow2" in argv and "-nographic" in argv and \
                any(QMP_SOCKET in arg for arg in argv):
            qemu_pids.append(int(entry))
    assert qemu_pids, "No qemu-system-x86_64 process has the required image, -nographic, and QMP socket arguments"

    socket_inode = None
    with open("/proc/net/unix") as f:
        next(f, None)
        for line in f:
            fields = line.split()
            if len(fields) >= 8 and fields[-1] == QMP_SOCKET:
                socket_inode = fields[6]
                break
    assert socket_inode, "QMP Unix socket is not registered in the kernel"

    owned_by_qemu = False
    for pid in qemu_pids:
        try:
            for fd in os.listdir(f"/proc/{pid}/fd"):
                try:
                    if os.readlink(f"/proc/{pid}/fd/{fd}") == f"socket:[{socket_inode}]":
                        owned_by_qemu = True
                        break
                except OSError:
                    pass
        except (FileNotFoundError, PermissionError):
            pass
    assert owned_by_qemu, "The QMP socket is not owned by the required QEMU process"

    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.settimeout(5)
        s.connect(QMP_SOCKET)
        stream = s.makefile("rwb", buffering=0)
        greeting = json.loads(stream.readline())
        assert "QMP" in greeting, f"Socket did not provide a QMP greeting: {greeting}"
        qmp_command(stream, "qmp_capabilities")
        status = qmp_command(stream, "query-status")
        assert isinstance(status, dict) and "status" in status


def expected_monitor_output():
    env = os.environ.copy()
    env["TZ"] = "America/New_York"
    env["LC_ALL"] = "C"
    components = env.get("PATH", "").split(":")
    if "/usr/local/sbin" not in components:
        env["PATH"] = "/usr/local/sbin:" + env.get("PATH", "")
    return subprocess.check_output([MONITOR], env=env, timeout=5)


def test_raw_tcp_service():
    expected_output = "HEARTBEAT_OK_78291"
    derived = expected_monitor_output()
    assert derived.decode() == expected_output
    try:
        with socket.create_connection(("127.0.0.1", 8040), timeout=5) as s:
            s.sendall(b"PING\n")
            response = recv_all(s)
            assert expected_output in response.decode("utf-8")
            assert response == derived, "Raw TCP response is not the exact stdout of legacy_monitor"
    except ConnectionRefusedError:
        pytest.fail("Could not connect to Raw TCP service on 127.0.0.1:8040")
    except socket.timeout:
        pytest.fail("Timeout connecting to or reading from Raw TCP service on 127.0.0.1:8040")


def test_http_service():
    expected_output = "HEARTBEAT_OK_78291"
    derived = expected_monitor_output()
    try:
        response = requests.get("http://127.0.0.1:8080/uptime", timeout=5)
        assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"
        assert expected_output in response.text
        assert response.content == derived, "HTTP body is not purely the exact stdout of legacy_monitor"
    except requests.exceptions.ConnectionError:
        pytest.fail("Could not connect to HTTP service at http://127.0.0.1:8080/uptime")
    except requests.exceptions.Timeout:
        pytest.fail("Timeout connecting to HTTP service at http://127.0.0.1:8080/uptime")


def test_services_reexecute_monitor_with_required_environment():
    nonce = "DYNAMIC_" + uuid.uuid4().hex
    invocation_log = f"/tmp/monitor-invocations-{uuid.uuid4().hex}"
    source = f"/tmp/monitor-probe-{uuid.uuid4().hex}.c"
    probe = source[:-2]
    backup = f"/tmp/legacy-monitor-backup-{uuid.uuid4().hex}"
    c_nonce = json.dumps(nonce)
    c_log = json.dumps(invocation_log)

    code = f'''#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>
int main(void) {{
  const char *tz=getenv("TZ"), *lc=getenv("LC_ALL"), *path=getenv("PATH");
  if (!tz || strcmp(tz,"America/New_York") || !lc || strcmp(lc,"C") ||
      !path || !strstr(path,"/usr/local/sbin")) return 41;
  int s=socket(AF_UNIX,SOCK_STREAM,0); struct sockaddr_un a;
  memset(&a,0,sizeof(a)); a.sun_family=AF_UNIX;
  strncpy(a.sun_path,"/tmp/legacy_qmp.sock",sizeof(a.sun_path)-1);
  if (s < 0 || connect(s,(struct sockaddr *)&a,sizeof(a)) < 0) return 42;
  close(s);
  FILE *f=fopen({c_log},"a"); if (!f) return 43;
  fputc('X',f); fclose(f);
  fputs({c_nonce},stdout); fflush(stdout); return 0;
}}
'''
    with open(source, "w") as f:
        f.write(code)
    run(["gcc", "-O2", source, "-o", probe])

    replaced = False
    try:
        os.replace(MONITOR, backup)
        replaced = True
        shutil.copy2(probe, MONITOR)
        os.chmod(MONITOR, 0o755)

        with socket.create_connection(("127.0.0.1", 8040), timeout=5) as s:
            s.sendall(b"PING\n")
            raw = recv_all(s)
        assert raw == nonce.encode(), "Raw service did not execute the current /app/legacy_monitor"
        assert os.path.exists(invocation_log) and open(invocation_log, "rb").read() == b"X"

        response = requests.get("http://127.0.0.1:8080/uptime", timeout=5)
        assert response.status_code == 200
        assert response.content == nonce.encode(), "HTTP service did not execute the current /app/legacy_monitor"
        assert open(invocation_log, "rb").read() == b"XX", "Each protocol must execute legacy_monitor per request"
    finally:
        if replaced:
            try:
                os.unlink(MONITOR)
            except FileNotFoundError:
                pass
            os.replace(backup, MONITOR)
        for path in (source, probe, invocation_log):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
