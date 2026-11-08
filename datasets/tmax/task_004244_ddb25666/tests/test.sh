#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import signal
import socket
import stat
import subprocess
import tempfile
import time
import pytest

C_FILE = "/home/user/prov_daemon.c"
EXECUTABLE = "/home/user/prov_daemon"
ACL_FILE = "/home/user/qemu_vnc.acl"
PORT = 8111


def listener_pids():
    """Return PIDs owning a listening socket on 127.0.0.1:8111."""
    inodes = set()
    expected = "0100007F:%04X" % PORT
    try:
        with open("/proc/net/tcp", "r") as f:
            next(f, None)
            for line in f:
                fields = line.split()
                if len(fields) > 9 and fields[1].upper() == expected and fields[3] == "0A":
                    inodes.add(fields[9])
    except OSError:
        pass

    pids = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(entry))
                    break
        except OSError:
            continue
    return pids


def pid_is_target_executable(pid):
    try:
        process_exe = os.stat(f"/proc/{pid}/exe")
        target_exe = os.stat(EXECUTABLE)
        return (process_exe.st_dev, process_exe.st_ino) == (target_exe.st_dev, target_exe.st_ino)
    except OSError:
        return False


def wait_for_listener(timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        pids = listener_pids()
        if pids:
            return pids
        time.sleep(0.1)
    return set()


def stop_listeners():
    pids = listener_pids()
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass

    deadline = time.time() + 3
    while time.time() < deadline and listener_pids():
        time.sleep(0.1)

    for pid in listener_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass

    deadline = time.time() + 2
    while time.time() < deadline and listener_pids():
        time.sleep(0.1)
    assert not listener_pids(), "Could not stop the existing listener on port 8111."


def exercise_protocol():
    # Remove the ACL file if it exists to ensure the daemon creates it.
    if os.path.exists(ACL_FILE):
        os.chmod(ACL_FILE, 0o666)
        os.remove(ACL_FILE)

    passcode = b"purple dinosaur\n"
    try:
        with socket.create_connection(("127.0.0.1", PORT), timeout=5) as s:
            s.sendall(passcode)
            response = s.recv(1024)
    except ConnectionRefusedError:
        pytest.fail("Daemon is not listening on 127.0.0.1:8111.")
    except Exception as e:
        pytest.fail(f"Failed to communicate with daemon: {e}")

    expected_response = b"VNC_ACL_UPDATED\n"
    assert response == expected_response, f"Expected response {expected_response}, got {response}"

    time.sleep(0.5)
    assert os.path.isfile(ACL_FILE), f"ACL file {ACL_FILE} was not created by the daemon."

    with open(ACL_FILE, "r") as f:
        contents = f.read()
    assert contents == "VNC_ACCESS=GRANTED\n", f"ACL file contents incorrect. Got: {contents!r}"

    perms = stat.S_IMODE(os.stat(ACL_FILE).st_mode)
    assert perms == 0o400, f"ACL file permissions should be 0400, got {oct(perms)}"


def test_final_state_and_rebuilt_c_daemon():
    # Preserve the original file-existence assertions.
    assert os.path.isfile(C_FILE), f"C source file {C_FILE} is missing."
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} is missing."

    # The submitted executable must be an executable ELF binary, not a script or dummy file.
    assert os.access(EXECUTABLE, os.X_OK), f"{EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{EXECUTABLE} is not an ELF executable."

    # The process which owns the required listening socket must be this executable.
    original_pids = wait_for_listener()
    assert original_pids, "Daemon is not listening on 127.0.0.1:8111."
    assert any(pid_is_target_executable(pid) for pid in original_pids), (
        "The process listening on port 8111 is not /home/user/prov_daemon."
    )

    # Preserve and run the original protocol and ACL assertions against the submitted process.
    exercise_protocol()

    # Rebuild the submitted source, then execute and exercise that build. This ensures the
    # required behavior is actually implemented by compilable C source rather than a proxy server.
    stop_listeners()
    fd, rebuilt = tempfile.mkstemp(prefix=".prov_daemon.rebuilt.", dir="/home/user")
    os.close(fd)
    os.unlink(rebuilt)
    try:
        result = subprocess.run(
            ["gcc", C_FILE, "-o", rebuilt],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, f"C source failed to compile:\n{result.stderr}"
        os.replace(rebuilt, EXECUTABLE)
    finally:
        if os.path.exists(rebuilt):
            os.unlink(rebuilt)

    subprocess.Popen(
        [EXECUTABLE],
        cwd="/home/user",
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )

    rebuilt_pids = wait_for_listener()
    assert rebuilt_pids, "Daemon rebuilt from prov_daemon.c did not listen on 127.0.0.1:8111."
    assert any(pid_is_target_executable(pid) for pid in rebuilt_pids), (
        "The rebuilt C executable is not the process listening on port 8111."
    )
    exercise_protocol()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
