#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import signal
import socket
import subprocess
import tempfile
import time

RESTORE = "/home/user/restore"
BACKEND_SCRIPT = "/home/user/backend_service/run_backend.sh"
BACKEND_SOCKET = "/home/user/backend_service/app.sock"
EXPECTED = b"RESTORE_VALID\n"


def process_info():
    result = {}
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/stat", "r") as f:
                stat = f.read().split()
            with open(f"/proc/{entry}/cmdline", "rb") as f:
                cmdline = f.read().replace(b"\0", b" ").decode(errors="replace")
            result[int(entry)] = {
                "ppid": int(stat[3]),
                "state": stat[2],
                "cmdline": cmdline,
            }
        except (FileNotFoundError, ProcessLookupError, PermissionError, IndexError, ValueError):
            pass
    return result


def socket_owner_pids(inode):
    owners = []
    target = f"socket:[{inode}]"
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    if os.readlink(os.path.join(fd_dir, fd)) == target:
                        owners.append(int(entry))
                        break
                except (FileNotFoundError, PermissionError, OSError):
                    pass
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return owners


def unix_listener_inode(path):
    try:
        with open("/proc/net/unix", "r") as f:
            for line in f:
                fields = line.split()
                if len(fields) >= 8 and fields[7] == path and fields[5] == "01":
                    return fields[6]
    except FileNotFoundError:
        pass
    return None


def tcp_listener_inodes(port):
    inodes = []
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10:
                        local = fields[1]
                        state = fields[3]
                        if state == "0A" and int(local.rsplit(":", 1)[1], 16) == port:
                            inodes.append(fields[9])
        except FileNotFoundError:
            pass
    return inodes


def is_descendant(pid, ancestors, info):
    seen = set()
    while pid > 1 and pid not in seen:
        if pid in ancestors:
            return True
        seen.add(pid)
        pid = info.get(pid, {}).get("ppid", 0)
    return False


def backend_request(timeout=1.0):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(timeout)
    try:
        s.connect(BACKEND_SOCKET)
        s.sendall(b"verifier-probe\n")
        data = b""
        while not data.endswith(b"\n"):
            chunk = s.recv(1024)
            if not chunk:
                break
            data += chunk
        return data
    finally:
        s.close()


def wait_for_backend(deadline):
    last_error = None
    while time.time() < deadline:
        try:
            return backend_request()
        except (OSError, socket.timeout) as exc:
            last_error = exc
            time.sleep(0.05)
    raise AssertionError(f"The supervised backend did not become available: {last_error}")


def test_restore_directory_exists():
    assert os.path.isdir(RESTORE), "The directory /home/user/restore does not exist."


def test_config_updated():
    config_path = f"{RESTORE}/config.ini"
    assert os.path.isfile(config_path), f"{config_path} is missing."
    with open(config_path, "r") as f:
        content = f.read()
    assert "upstream=/home/user/backend_service/app.sock" in content, "The upstream socket path in config.ini was not updated correctly."


def test_allowed_users_updated():
    db_path = f"{RESTORE}/allowed_users.db"
    assert os.path.isfile(db_path), f"{db_path} is missing."
    with open(db_path, "r") as f:
        users = [line.strip() for line in f]
    assert "backup_operator" in users, "The user 'backup_operator' was not added to allowed_users.db."


def test_run_backend_script():
    script_path = BACKEND_SCRIPT
    assert os.path.isfile(script_path), f"{script_path} is missing."
    with open(script_path, "r") as f:
        content = f.read()

    assert re.search(r'\b(while|until)\b', content), "The run_backend.sh script does not contain a loop to automatically restart the listener."
    assert re.search(r'\b(socat|nc)\b', content), "The run_backend.sh script does not use socat or nc."
    assert BACKEND_SOCKET in content, "The run_backend.sh script does not reference the correct UNIX socket path."

    info = process_info()
    supervisors = {
        pid for pid, details in info.items()
        if details["state"] != "Z" and BACKEND_SCRIPT in details["cmdline"]
    }
    assert supervisors, "The backend supervisor script is not running in the background."

    assert wait_for_backend(time.time() + 3) == EXPECTED, "The mock backend did not return the exact required response."

    inode = unix_listener_inode(BACKEND_SOCKET)
    assert inode is not None, "No process is listening on the required UNIX socket."
    owners = socket_owner_pids(inode)
    info = process_info()
    assert owners, "Could not identify the process listening on the backend socket."
    assert any(is_descendant(pid, supervisors, info) for pid in owners), "The socket listener is not supervised by run_backend.sh."

    for pid in owners:
        if pid not in supervisors:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass

    assert wait_for_backend(time.time() + 4) == EXPECTED, "The supervisor did not restart the socket listener after it was killed."
    live = process_info()
    assert any(pid in live and live[pid]["state"] != "Z" for pid in supervisors), "The backend supervisor exited during the restart test."


def test_multiplexer_c_fixed():
    c_path = f"{RESTORE}/src/multiplexer.c"
    assert os.path.isfile(c_path), f"{c_path} is missing."
    with open(c_path, "r") as f:
        content = f.read()

    content_no_spaces = content.replace(" ", "").replace("\t", "")
    assert 'setenv("TZ","UTC",1);' in content_no_spaces, "The multiplexer.c source file does not contain the required setenv call to fix the timezone bug."
    assert re.search(r'\bint\s+main\s*\([^)]*\)\s*\{\s*setenv\s*\(\s*"TZ"\s*,\s*"UTC"\s*,\s*1\s*\)\s*;', content, re.S), "The required setenv call is not at the beginning of main()."


def test_compiled_multiplexer_end_to_end():
    binary = f"{RESTORE}/multiplexer"
    source = f"{RESTORE}/src/multiplexer.c"
    assert os.path.isfile(binary), "The compiled multiplexer is missing."
    assert os.access(binary, os.X_OK), "The compiled multiplexer is not executable."
    with open(binary, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The multiplexer is not a compiled ELF executable."

    fd, rebuilt = tempfile.mkstemp(prefix="multiplexer-rebuilt-")
    os.close(fd)
    proc = None
    try:
        subprocess.run(["gcc", source, "-o", rebuilt], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        with open(binary, "rb") as f:
            submitted_bytes = f.read()
        with open(rebuilt, "rb") as f:
            rebuilt_bytes = f.read()
        assert submitted_bytes == rebuilt_bytes, "The multiplexer executable does not match the restored source compiled with the required command."

        for inode in tcp_listener_inodes(8080):
            for pid in socket_owner_pids(inode):
                try:
                    os.kill(pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
        deadline = time.time() + 2
        while tcp_listener_inodes(8080) and time.time() < deadline:
            time.sleep(0.05)
        assert not tcp_listener_inodes(8080), "Port 8080 is occupied by a stale process."

        proc = subprocess.Popen([binary], cwd=RESTORE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        deadline = time.time() + 3
        while time.time() < deadline and not tcp_listener_inodes(8080):
            assert proc.poll() is None, "The multiplexer exited before listening on port 8080."
            time.sleep(0.05)
        assert tcp_listener_inodes(8080), "The multiplexer did not listen on 127.0.0.1:8080."
        assert proc.poll() is None, "The multiplexer was not alive for the runtime test."

        payload = f"backup_operator:{secrets.token_hex(12)}".encode()
        with socket.create_connection(("127.0.0.1", 8080), timeout=2) as client:
            client.sendall(payload)
            client.shutdown(socket.SHUT_WR)
            response = b""
            while True:
                chunk = client.recv(1024)
                if not chunk:
                    break
                response += chunk
        assert response == EXPECTED, f"The multiplexer returned {response!r}, not the exact backend response."
        assert proc.wait(timeout=3) == 0, "The multiplexer did not exit successfully after serving the request."
    finally:
        if proc is not None and proc.poll() is None:
            proc.kill()
            proc.wait()
        try:
            os.unlink(rebuilt)
        except FileNotFoundError:
            pass


def test_restore_success_log():
    log_path = "/home/user/restore_success.log"
    assert os.path.isfile(log_path), f"{log_path} is missing. The multiplexer might not have been compiled, run, or queried correctly."
    with open(log_path, "r") as f:
        content = f.read()
    assert "RESTORE_VALID" in content, "The restore_success.log does not contain the expected response 'RESTORE_VALID'."
    with open(log_path, "rb") as f:
        assert f.read() == EXPECTED, "The restore_success.log does not contain the exact response received from the backend."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
