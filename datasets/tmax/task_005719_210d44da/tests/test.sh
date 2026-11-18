#!/bin/bash
set +e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import socket
import subprocess
import time

import pytest

SOURCE = "/home/user/source-repo"
BARE = "/home/user/edge-update.git"
DEPLOYED = "/home/user/deployed"
HOOK = "/home/user/edge-update.git/hooks/post-receive"
MONITOR = "/home/user/deployed/monitor"
PIDFILE = "/home/user/monitor.pid"
LOG = "/home/user/deploy.log"


def git(repo, *args, timeout=15):
    return subprocess.run(
        ["git", "-c", "safe.directory=*", "-C", repo, *args],
        capture_output=True,
        text=True,
        check=True,
        timeout=timeout,
    )


def read_pid():
    assert os.path.exists(PIDFILE), f"{PIDFILE} does not exist."
    value = open(PIDFILE).read().strip()
    assert value.isdigit(), f"PID file {PIDFILE} does not contain a valid integer."
    return int(value)


def process_alive(pid):
    try:
        with open(f"/proc/{pid}/stat") as f:
            state = f.read().split()[2]
        return state != "Z"
    except (FileNotFoundError, ProcessLookupError, IndexError):
        return False


def assert_monitor_process(pid):
    assert process_alive(pid), f"Process with PID {pid} is not running."
    try:
        assert os.path.samefile(f"/proc/{pid}/exe", MONITOR), (
            f"PID {pid} is not the deployed monitor executable."
        )
    except FileNotFoundError:
        pytest.fail(f"Could not inspect executable for PID {pid}.")


def exchange(payload, timeout=2.0):
    with socket.create_connection(("127.0.0.1", 9090), timeout=timeout) as sock:
        sock.settimeout(timeout)
        sock.sendall(payload)
        chunks = []
        while True:
            data = sock.recv(1024)
            if not data:
                break
            chunks.append(data)
        return b"".join(chunks)


def test_repositories_and_directories_exist():
    assert os.path.exists(BARE), "Bare repository /home/user/edge-update.git does not exist."
    assert os.path.exists(DEPLOYED), "Deployment directory /home/user/deployed does not exist."
    assert os.path.exists(SOURCE), "Source repository /home/user/source-repo does not exist."
    assert os.path.exists(HOOK), "post-receive hook does not exist."
    assert os.path.exists(MONITOR), "Compiled monitor executable does not exist in deployed directory."


def test_deploy_log():
    assert os.path.exists(LOG), "/home/user/deploy.log does not exist."
    try:
        latest_commit = git(SOURCE, "rev-parse", "main").stdout.strip()
    except subprocess.CalledProcessError:
        pytest.fail("Could not retrieve commit hash from /home/user/source-repo.")

    expected_log = f"DEPLOYED: {latest_commit}"
    with open(LOG) as f:
        log_content = f.read()
    assert expected_log in log_content, f"Expected string '{expected_log}' not found in {LOG}."


def test_monitor_process_running():
    pid = read_pid()
    try:
        os.kill(pid, 0)
    except OSError:
        pytest.fail(f"Process with PID {pid} (from {PIDFILE}) is not running.")


def test_tcp_ping_pong():
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.settimeout(2.0)
            sock.connect(("127.0.0.1", 9090))
            sock.sendall(b"PING\n")
            response = sock.recv(1024).decode("utf-8")
            assert response == "PONG\n", f"Expected 'PONG\\n', received {response!r}"
    except ConnectionRefusedError:
        pytest.fail("Connection refused on 127.0.0.1:9090. The monitor daemon is not listening.")
    except socket.timeout:
        pytest.fail("Connection timed out when trying to read from 127.0.0.1:9090.")


def test_repository_configuration_and_initial_deployment():
    assert git(BARE, "rev-parse", "--is-bare-repository").stdout.strip() == "true", (
        f"{BARE} is not a bare Git repository."
    )
    assert git(SOURCE, "rev-parse", "--is-bare-repository").stdout.strip() == "false", (
        f"{SOURCE} is not a regular Git repository."
    )
    assert os.path.isfile(HOOK), "post-receive is not a regular file."
    assert os.access(HOOK, os.X_OK), "post-receive hook is not executable."
    assert os.path.isfile(os.path.join(SOURCE, "device_monitor.c")), "device_monitor.c is missing."

    tracked = git(SOURCE, "ls-tree", "-r", "--name-only", "main").stdout.splitlines()
    assert "device_monitor.c" in tracked, "device_monitor.c is not committed on main."

    origin = git(SOURCE, "remote", "get-url", "origin").stdout.strip()
    push_origin = git(SOURCE, "remote", "get-url", "--push", "origin").stdout.strip()

    def local_remote_path(value):
        if value.startswith("file://"):
            value = value[7:]
        return os.path.realpath(value)

    assert local_remote_path(origin) == os.path.realpath(BARE), "origin does not reference edge-update.git."
    assert local_remote_path(push_origin) == os.path.realpath(BARE), "origin push URL does not reference edge-update.git."

    source_rev = git(SOURCE, "rev-parse", "main").stdout.strip()
    bare_rev = git(BARE, "rev-parse", "refs/heads/main").stdout.strip()
    assert bare_rev == source_rev, "The source main branch was not pushed to the bare repository."

    committed_source = git(SOURCE, "show", "main:device_monitor.c").stdout
    with open(os.path.join(DEPLOYED, "device_monitor.c")) as f:
        deployed_source = f.read()
    assert deployed_source == committed_source, "The committed source was not checked out into deployed."
    assert os.access(MONITOR, os.X_OK), "The deployed monitor is not executable."
    with open(MONITOR, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The deployed monitor is not a compiled ELF executable."
    assert_monitor_process(read_pid())


def test_post_receive_performs_fresh_checkout_compile_restart_and_log():
    old_pid = read_pid()
    assert_monitor_process(old_pid)
    with open(LOG, "rb") as f:
        old_log = f.read()

    token = secrets.token_hex(12)
    request = f"VERIFY_{token}\\n"
    response = f"OK_{token}\\n"
    program = r'''#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>

static int send_all(int fd, const char *p, size_t n) {
    while (n) {
        ssize_t w = send(fd, p, n, 0);
        if (w < 0) { if (errno == EINTR) continue; return -1; }
        p += w; n -= (size_t)w;
    }
    return 0;
}

int main(void) {
    FILE *pf = fopen("/home/user/monitor.pid", "w");
    if (!pf) return 2;
    fprintf(pf, "%ld\n", (long)getpid());
    fclose(pf);

    int s = socket(AF_INET, SOCK_STREAM, 0);
    if (s < 0) return 3;
    int yes = 1;
    setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
    struct sockaddr_in a;
    memset(&a, 0, sizeof(a));
    a.sin_family = AF_INET;
    a.sin_port = htons(9090);
    inet_pton(AF_INET, "127.0.0.1", &a.sin_addr);
    if (bind(s, (struct sockaddr *)&a, sizeof(a)) < 0) return 4;
    if (listen(s, 16) < 0) return 5;

    for (;;) {
        int c = accept(s, NULL, NULL);
        if (c < 0) { if (errno == EINTR) continue; return 6; }
        char buf[512];
        size_t used = 0;
        while (used + 1 < sizeof(buf)) {
            ssize_t n = recv(c, buf + used, sizeof(buf) - 1 - used, 0);
            if (n <= 0) break;
            used += (size_t)n;
            if (memchr(buf, '\n', used)) break;
        }
        buf[used] = 0;
        if (strcmp(buf, "PING\n") == 0) {
            send_all(c, "PONG\n", 5);
        } else if (strcmp(buf, "__REQUEST__") == 0) {
            send_all(c, "__RESPONSE__", strlen("__RESPONSE__"));
        }
        close(c);
    }
}
'''.replace("__REQUEST__", request).replace("__RESPONSE__", response)

    source_path = os.path.join(SOURCE, "device_monitor.c")
    with open(source_path, "w") as f:
        f.write(program)

    git(SOURCE, "add", "device_monitor.c")
    subprocess.run(
        ["git", "-c", "safe.directory=*", "-c", "user.name=Verifier", "-c",
         "user.email=verifier@example.invalid", "-C", SOURCE, "commit", "-m",
         f"verification deployment {token}"],
        capture_output=True, text=True, check=True, timeout=15,
    )
    new_rev = git(SOURCE, "rev-parse", "main").stdout.strip()

    try:
        git(SOURCE, "push", "origin", "main", timeout=30)
    except subprocess.CalledProcessError as exc:
        pytest.fail(f"Fresh push to origin failed: {exc.stderr}")
    except subprocess.TimeoutExpired:
        pytest.fail("Fresh push to origin timed out; the post-receive hook did not finish correctly.")

    assert git(BARE, "rev-parse", "refs/heads/main").stdout.strip() == new_rev, (
        "The fresh main commit did not reach the bare repository."
    )
    with open(os.path.join(DEPLOYED, "device_monitor.c")) as f:
        assert f.read() == program, "The post-receive hook did not check out the freshly pushed source."

    deadline = time.time() + 8
    new_pid = None
    while time.time() < deadline:
        try:
            candidate = read_pid()
            if candidate != old_pid and process_alive(candidate):
                new_pid = candidate
                break
        except (AssertionError, OSError):
            pass
        time.sleep(0.1)
    assert new_pid is not None, "The hook did not replace the old daemon with a new process."
    assert not process_alive(old_pid), "The old daemon was not terminated by the hook."
    assert_monitor_process(new_pid)

    challenge_result = None
    deadline = time.time() + 8
    while time.time() < deadline:
        try:
            challenge_result = exchange(request.encode())
            break
        except (ConnectionRefusedError, ConnectionResetError, socket.timeout, OSError):
            time.sleep(0.1)
    assert challenge_result == response.encode(), (
        "The running daemon was not compiled from the freshly pushed C source."
    )
    for _ in range(3):
        assert exchange(b"PING\n") == b"PONG\n", (
            "The newly deployed monitor did not continue serving and closing client connections."
        )

    with open(LOG, "rb") as f:
        new_log = f.read()
    assert new_log.startswith(old_log), "The deployment hook replaced or truncated deploy.log."
    appended = new_log[len(old_log):]
    expected = f"DEPLOYED: {new_rev}".encode()
    assert appended in (expected, expected + b"\n"), (
        f"The fresh push must append exactly 'DEPLOYED: {new_rev}' to deploy.log; got {appended!r}."
    )
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
