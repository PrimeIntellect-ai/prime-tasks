#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import grp
import os
import pwd
import signal
import subprocess
import uuid

import pytest

USER = pwd.getpwnam("user")
USER_GROUPS = os.getgrouplist(USER.pw_name, USER.pw_gid)
DEPLOYERS_GID = grp.getgrnam("deployers").gr_gid


def user_preexec(groups=None):
    selected = USER_GROUPS if groups is None else groups

    def demote():
        os.setgroups(selected)
        os.setgid(USER.pw_gid)
        os.setuid(USER.pw_uid)

    return demote


def run_as_user(argv, timeout=15, env=None, groups=None):
    child_env = os.environ.copy()
    if env:
        child_env.update(env)
    return subprocess.run(
        argv,
        cwd="/home/user",
        env=child_env,
        capture_output=True,
        text=True,
        timeout=timeout,
        preexec_fn=user_preexec(groups),
    )


def server_pids():
    found = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            target = os.path.realpath(f"/proc/{name}/exe")
        except OSError:
            continue
        if target == "/home/user/deploy/server":
            found.append(int(name))
    return found


def kill_servers():
    for pid in server_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def assert_no_server():
    assert not server_pids(), f"Server process was not terminated cleanly. PIDs found: {server_pids()}"


def test_client_c_fixed():
    client_path = "/home/user/src/client.c"
    assert os.path.isfile(client_path), f"{client_path} is missing."
    with open(client_path, "r") as f:
        content = f.read()
    assert "127.0.0.1" in content, "client.c does not contain the correct IP address (127.0.0.1)."
    assert "8080" in content, "client.c does not contain the correct port (8080)."
    assert "192.168.1.100" not in content, "client.c still contains the old incorrect IP address."
    assert "9090" not in content, "client.c still contains the old incorrect port."


def test_preflight_c_exists_and_checks():
    preflight_path = "/home/user/src/preflight.c"
    assert os.path.isfile(preflight_path), f"{preflight_path} is missing."
    with open(preflight_path, "r") as f:
        content = f.read()
    assert "statvfs" in content, "preflight.c does not use the statvfs system call."
    assert "deployers" in content, "preflight.c does not check for the 'deployers' group."
    assert "PREFLIGHT OK" in content, "preflight.c does not print 'PREFLIGHT OK'."


def test_pipeline_sh_executable():
    pipeline_path = "/home/user/pipeline.sh"
    assert os.path.isfile(pipeline_path), f"{pipeline_path} is missing."
    assert os.access(pipeline_path, os.X_OK), f"{pipeline_path} is not executable."


def test_pipeline_builds_runs_and_uses_network():
    pipeline = "/home/user/pipeline.sh"
    server_source = "/home/user/src/server.c"
    original_server = open(server_source, "r").read()
    token = "VERIFY_" + uuid.uuid4().hex
    marker = "/tmp/server_accept_" + uuid.uuid4().hex

    instrumented_server = f'''#include <arpa/inet.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>
int main(void) {{
    int s = socket(AF_INET, SOCK_STREAM, 0), c, one = 1;
    struct sockaddr_in a;
    if (s < 0) return 2;
    setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
    memset(&a, 0, sizeof(a));
    a.sin_family = AF_INET;
    a.sin_addr.s_addr = inet_addr("127.0.0.1");
    a.sin_port = htons(8080);
    if (bind(s, (struct sockaddr *)&a, sizeof(a)) || listen(s, 1)) return 3;
    c = accept(s, NULL, NULL);
    if (c < 0) return 4;
    const char msg[] = "{token}\\n";
    if (send(c, msg, sizeof(msg)-1, 0) != sizeof(msg)-1) return 5;
    close(c);
    int fd = open("{marker}", O_WRONLY|O_CREAT|O_TRUNC, 0666);
    if (fd < 0) return 6;
    write(fd, "accepted\\n", 9);
    close(fd);
    sleep(30);
    return 0;
}}
'''

    try:
        kill_servers()
        for path in ("/home/user/deploy/server", "/home/user/deploy/client", "/home/user/deploy/result.log", marker):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
        with open(server_source, "w") as f:
            f.write(instrumented_server)
        os.chown(server_source, USER.pw_uid, USER.pw_gid)

        result = run_as_user([pipeline], timeout=15)
        assert result.returncode == 0, (
            f"pipeline.sh failed with exit code {result.returncode}.\n"
            f"Stdout: {result.stdout}\nStderr: {result.stderr}"
        )
        assert os.path.isfile(marker), "The pipeline's server never accepted a client connection."
        assert_no_server()

        for artifact in ("/home/user/preflight", "/home/user/deploy/server", "/home/user/deploy/client"):
            assert os.path.isfile(artifact), f"{artifact} was not built by the pipeline."
            with open(artifact, "rb") as f:
                assert f.read(4) == b"\x7fELF", f"{artifact} is not a compiled executable."

        result_log = "/home/user/deploy/result.log"
        assert os.path.isfile(result_log), f"{result_log} was not created by the pipeline."
        with open(result_log, "r") as f:
            assert f.read() == token + "\n", "result.log did not contain data received from the test server."
    finally:
        with open(server_source, "w") as f:
            f.write(original_server)
        os.chown(server_source, USER.pw_uid, USER.pw_gid)
        kill_servers()
        try:
            os.remove(marker)
        except FileNotFoundError:
            pass


def test_pipeline_stops_when_preflight_fails():
    pipeline = "/home/user/pipeline.sh"
    preflight_source = "/home/user/src/preflight.c"
    original = open(preflight_source, "r").read()
    marker = "/tmp/preflight_ran_" + uuid.uuid4().hex
    failing_source = f'''#include <fcntl.h>
#include <unistd.h>
int main(void) {{
    int fd = open("{marker}", O_WRONLY|O_CREAT|O_TRUNC, 0666);
    if (fd >= 0) {{ write(fd, "ran\\n", 4); close(fd); }}
    return 73;
}}
'''
    try:
        kill_servers()
        for path in (marker, "/home/user/deploy/server", "/home/user/deploy/client", "/home/user/deploy/result.log"):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
        with open(preflight_source, "w") as f:
            f.write(failing_source)
        os.chown(preflight_source, USER.pw_uid, USER.pw_gid)

        result = run_as_user([pipeline], timeout=10)
        assert result.returncode != 0, "pipeline.sh ignored a failing pre-flight checker."
        assert os.path.isfile(marker), "pipeline.sh did not compile and run preflight.c."
        assert not os.path.exists("/home/user/deploy/server"), "Server was built before a successful pre-flight check."
        assert not os.path.exists("/home/user/deploy/client"), "Client was built before a successful pre-flight check."
        assert not os.path.exists("/home/user/deploy/result.log"), "Deployment test ran despite pre-flight failure."
        assert_no_server()
    finally:
        with open(preflight_source, "w") as f:
            f.write(original)
        os.chown(preflight_source, USER.pw_uid, USER.pw_gid)
        kill_servers()
        try:
            os.remove(marker)
        except FileNotFoundError:
            pass


def test_pipeline_execution_and_result():
    pipeline_path = "/home/user/pipeline.sh"
    result = run_as_user([pipeline_path], timeout=15)
    assert result.returncode == 0, (
        f"pipeline.sh failed with exit code {result.returncode}.\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )
    result_log_path = "/home/user/deploy/result.log"
    assert os.path.isfile(result_log_path), f"{result_log_path} was not created by the pipeline."
    with open(result_log_path, "r") as f:
        log_content = f.read()
    assert log_content == "CONNECTION_SUCCESSFUL\n", f"result.log contains unexpected content: {repr(log_content)}"
    assert_no_server()


def test_preflight_programmatic_group_and_storage_checks():
    executable = "/home/user/preflight"
    assert os.path.isfile(executable), "The pipeline did not compile /home/user/preflight."

    success = run_as_user([executable], groups=USER_GROUPS)
    assert success.returncode == 0, f"Preflight failed for a deployers member: {success.stderr}"
    assert success.stdout == "PREFLIGHT OK\n", f"Unexpected successful preflight output: {success.stdout!r}"

    groups_without_deployers = [gid for gid in USER_GROUPS if gid != DEPLOYERS_GID]
    no_group = run_as_user([executable], groups=groups_without_deployers)
    assert no_group.returncode == 1, "Preflight did not fail when the same user lacked deployers membership."
    assert "PREFLIGHT OK" not in no_group.stdout

    suffix = uuid.uuid4().hex
    source = f"/tmp/statvfs_override_{suffix}.c"
    library = f"/tmp/statvfs_override_{suffix}.so"
    marker = f"/tmp/statvfs_called_{suffix}"
    code = f'''#define _GNU_SOURCE
#include <fcntl.h>
#include <string.h>
#include <sys/statvfs.h>
#include <unistd.h>
int statvfs(const char *path, struct statvfs *buf) {{
    if (strcmp(path, "/home/user/deploy") != 0) return -1;
    int fd = open("{marker}", O_WRONLY|O_CREAT|O_TRUNC, 0666);
    if (fd >= 0) {{ write(fd, "called\\n", 7); close(fd); }}
    memset(buf, 0, sizeof(*buf));
    buf->f_frsize = 4096;
    buf->f_bavail = 0;
    return 0;
}}
'''
    try:
        with open(source, "w") as f:
            f.write(code)
        built = subprocess.run(["gcc", "-shared", "-fPIC", source, "-o", library], capture_output=True, text=True)
        assert built.returncode == 0, built.stderr
        os.chmod(library, 0o755)
        low_space = run_as_user([executable], env={"LD_PRELOAD": library}, groups=USER_GROUPS)
        assert os.path.isfile(marker), "Preflight did not call statvfs for /home/user/deploy."
        assert low_space.returncode == 1, "Preflight did not fail when available storage was below 1,000,000 bytes."
        assert "PREFLIGHT OK" not in low_space.stdout
    finally:
        for path in (source, library, marker):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass


def test_server_process_terminated():
    assert_no_server()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
