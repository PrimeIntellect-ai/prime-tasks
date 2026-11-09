#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import socket
import subprocess
import time
import secrets

DAEMON = "/home/user/bin/daemon"
SOURCE = "/home/user/_service/daemon.c"
SOCKET = "/home/user/_service/tmp/backend.sock"
LINK = "/home/user/proxy/run/upstream.sock"
CHECKER = "/home/user/proxy/check_upstream.sh"
STATUS = "/home/user/proxy/status.log"
SCRIPT = "/home/user/bin/start_stack.sh"


def daemon_pids():
    result = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            executable = os.readlink(f"/proc/{entry}/exe")
        except OSError:
            continue
        if executable == DAEMON or executable == DAEMON + " (deleted)":
            result.append(int(entry))
    return result


def stop_daemons():
    for pid in daemon_pids():
        try:
            os.kill(pid, 15)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while daemon_pids() and time.time() < deadline:
        time.sleep(0.05)
    for pid in daemon_pids():
        try:
            os.kill(pid, 9)
        except ProcessLookupError:
            pass
    time.sleep(0.1)


def wait_for_socket(path, timeout=3):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            if stat.S_ISSOCK(os.stat(path).st_mode):
                return
        except (FileNotFoundError, OSError):
            pass
        time.sleep(0.05)
    raise AssertionError(f"{path} did not become a live UNIX socket")


def assert_connectable(path):
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(1)
    try:
        client.connect(path)
    finally:
        client.close()


def test_status_log_contents():
    log_path = "/home/user/proxy/status.log"
    assert os.path.exists(log_path), f"{log_path} does not exist."

    with open(log_path, "r") as f:
        content = f.read().strip()

    expected_content = "200 OK: Upstream connected"
    assert content == expected_content, f"Expected '{expected_content}' in {log_path}, got '{content}'"


def test_symlink_created_correctly():
    symlink_path = "/home/user/proxy/run/upstream.sock"
    expected_target = "/home/user/_service/tmp/backend.sock"

    assert os.path.islink(symlink_path), f"{symlink_path} is not a symbolic link."

    actual_target = os.readlink(symlink_path)
    assert actual_target == expected_target, f"Symlink points to {actual_target}, expected {expected_target}"
    assert os.path.exists(symlink_path), f"{symlink_path} is dangling."
    assert stat.S_ISSOCK(os.stat(symlink_path).st_mode), f"{symlink_path} does not resolve to a UNIX socket."
    assert_connectable(symlink_path)
    assert daemon_pids(), f"No running process is executing {DAEMON}."


def test_bash_profile_updated():
    profile_path = "/home/user/.bash_profile"
    assert os.path.exists(profile_path), f"{profile_path} does not exist."

    with open(profile_path, "r") as f:
        content = f.read()

    assert 'SOCKET_MAPPING_DIR="/home/user/proxy/run"' in content, \
        f"SOCKET_MAPPING_DIR assignment missing in {profile_path}."

    assert '/home/user/bin' in content and 'PATH' in content, \
        f"PATH update for /home/user/bin missing in {profile_path}."


def test_start_stack_script_requirements():
    script_path = "/home/user/bin/start_stack.sh"
    assert os.path.exists(script_path), f"{script_path} does not exist."

    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"{script_path} is not executable."

    with open(script_path, "r") as f:
        content = f.read()

    assert re.search(r'\bdf\b', content), f"'df' command missing in {script_path}."
    assert re.search(r'\b(grep|awk|sed)\b', content), f"Text processing tool (grep, awk, or sed) missing in {script_path}."
    assert "daemon.c" in content, f"'daemon.c' reference missing in {script_path}."
    assert "ln -s" in content or "ln -sf" in content, f"'ln -s' command missing in {script_path}."


def test_daemon_compiled():
    daemon_path = "/home/user/bin/daemon"
    assert os.path.exists(daemon_path), f"Compiled daemon {daemon_path} does not exist."

    st = os.stat(daemon_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"{daemon_path} is not executable."
    with open(daemon_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{daemon_path} is not a compiled ELF executable."


def test_directories_exist():
    dirs = [
        "/home/user/bin",
        "/home/user/proxy/run",
        "/home/user/_service/tmp"
    ]
    for d in dirs:
        assert os.path.isdir(d), f"Directory {d} was not created."


def test_compiled_daemon_really_creates_and_listens_on_socket():
    stop_daemons()
    try:
        if os.path.lexists(SOCKET):
            os.unlink(SOCKET)
        proc = subprocess.Popen([DAEMON], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        wait_for_socket(SOCKET)
        assert proc.poll() is None, "Compiled daemon exited instead of remaining active."
        assert_connectable(SOCKET)
    finally:
        stop_daemons()
        if os.path.lexists(SOCKET):
            os.unlink(SOCKET)


def test_start_stack_executes_dynamic_end_to_end_workflow():
    source_data = open(SOURCE, "rb").read()
    daemon_data = open(DAEMON, "rb").read()
    daemon_mode = stat.S_IMODE(os.stat(DAEMON).st_mode)
    checker_data = open(CHECKER, "rb").read()
    checker_mode = stat.S_IMODE(os.stat(CHECKER).st_mode)

    token = "VERIFIER_" + secrets.token_hex(12)
    alternate_socket = f"/home/user/_service/tmp/{token}.sock"
    replacement_binary = DAEMON + ".verifier-build"

    try:
        stop_daemons()
        for path in (LINK, SOCKET, alternate_socket, STATUS, replacement_binary):
            if os.path.lexists(path):
                os.unlink(path)

        source_text = source_data.decode()
        changed, count = re.subn(
            r'(#define\s+SOCKET_PATH\s+")[^"]*(")',
            lambda m: m.group(1) + alternate_socket + m.group(2),
            source_text,
            count=1,
        )
        assert count == 1, "Could not locate SOCKET_PATH in daemon.c"
        with open(SOURCE, "w") as f:
            f.write(changed)

        subprocess.run(["gcc", SOURCE, "-o", replacement_binary], check=True)
        os.chmod(replacement_binary, daemon_mode)
        os.replace(replacement_binary, DAEMON)

        checker = f'''#!/bin/bash
if [ -S "$SOCKET_MAPPING_DIR/upstream.sock" ]; then
    echo "{token}"
    exit 0
else
    echo "socket validation failed"
    exit 1
fi
'''
        with open(CHECKER, "w") as f:
            f.write(checker)
        os.chmod(CHECKER, checker_mode)

        env = os.environ.copy()
        env["SOCKET_MAPPING_DIR"] = "/home/user/proxy/run"
        completed = subprocess.run(
            [SCRIPT],
            env=env,
            cwd="/home/user",
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=12,
        )
        assert completed.returncode == 0, f"{SCRIPT} exited with {completed.returncode}"

        assert os.path.islink(LINK), f"{SCRIPT} did not create {LINK} as a symlink."
        assert os.readlink(LINK) == alternate_socket, \
            "start_stack.sh did not dynamically extract the changed SOCKET_PATH from daemon.c."
        wait_for_socket(LINK)
        assert_connectable(LINK)
        assert daemon_pids(), f"{SCRIPT} did not leave the daemon running."
        assert os.path.exists(STATUS), f"{SCRIPT} did not create {STATUS}."
        with open(STATUS) as f:
            assert f.read().strip() == token, \
                "start_stack.sh did not execute check_upstream.sh and redirect its output to status.log."
    finally:
        stop_daemons()
        for path in (LINK, SOCKET, alternate_socket, replacement_binary):
            if os.path.lexists(path):
                os.unlink(path)
        with open(SOURCE, "wb") as f:
            f.write(source_data)
        restore_binary = DAEMON + ".restore"
        with open(restore_binary, "wb") as f:
            f.write(daemon_data)
        os.chmod(restore_binary, daemon_mode)
        os.replace(restore_binary, DAEMON)
        with open(CHECKER, "wb") as f:
            f.write(checker_data)
        os.chmod(CHECKER, checker_mode)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
