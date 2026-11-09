#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import signal
import socket
import subprocess
import tarfile
import tempfile
import time

SERVER_PATH = "/home/user/restore/server"
SOURCE_PATH = "/home/user/restore/server.c"
WATCHDOG_PATH = "/home/user/watchdog.sh"
EXPECTED = b"BACKUP_RESTORE_SUCCESSFUL\n"


def receive_status():
    with socket.create_connection(("127.0.0.1", 8080), timeout=2.0) as s:
        s.settimeout(2.0)
        chunks = []
        while True:
            data = s.recv(1024)
            if not data:
                break
            chunks.append(data)
        return b"".join(chunks)


def listener_pids():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10:
                        local = fields[1]
                        state = fields[3]
                        if state == "0A" and local.rsplit(":", 1)[-1].upper() == "1F90":
                            inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    pids.add(int(name))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return pids


def stop_port_8080():
    pids = listener_pids()
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and listener_pids():
        time.sleep(0.05)
    for pid in listener_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and listener_pids():
        time.sleep(0.05)
    assert not listener_pids(), "Could not clear port 8080 for supervision test"


def wait_for_listener(timeout=3):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if listener_pids():
            return
        time.sleep(0.05)
    raise AssertionError("No process began listening on port 8080")


def run_watchdog():
    subprocess.run(
        ["runuser", "-u", "user", "--", WATCHDOG_PATH],
        check=True,
        timeout=5,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def test_server_executable_exists():
    """Check that /home/user/restore/server exists and is executable."""
    assert os.path.isfile(SERVER_PATH), f"Executable {SERVER_PATH} does not exist."
    assert os.access(SERVER_PATH, os.X_OK), f"File {SERVER_PATH} is not executable."
    with open(SERVER_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{SERVER_PATH} is not a compiled ELF executable"


def test_watchdog_script_exists():
    """Check that /home/user/watchdog.sh exists and is executable."""
    assert os.path.isfile(WATCHDOG_PATH), f"Watchdog script {WATCHDOG_PATH} does not exist."
    assert os.access(WATCHDOG_PATH, os.X_OK), f"Watchdog script {WATCHDOG_PATH} is not executable."


def test_archive_was_restored_and_source_modified():
    assert os.path.isfile(SOURCE_PATH), f"Restored source {SOURCE_PATH} does not exist"
    with tarfile.open("/home/user/backup.tar.gz", "r:gz") as archive:
        member = archive.getmember("server.c")
        original = archive.extractfile(member).read().decode("utf-8")
    with open(SOURCE_PATH) as f:
        restored = f.read()

    assert "BACKUP_RESTORE_SUCCESSFUL" in restored
    assert "socket(" in restored and "bind(" in restored and "listen(" in restored and "accept(" in restored
    assert re.search(r"htons\s*\(\s*80\s*\)", original), "Backup source did not contain the expected port"
    assert not re.search(r"htons\s*\(\s*80\s*\)", restored), "Restored source still binds to port 80"
    assert re.search(r"htons\s*\(\s*8080\s*\)", restored), "Restored source does not bind to port 8080"

    fd, compiled_path = tempfile.mkstemp(prefix="restored-server-")
    os.close(fd)
    os.unlink(compiled_path)
    try:
        subprocess.run(
            ["gcc", SOURCE_PATH, "-o", compiled_path],
            check=True,
            timeout=15,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        stop_port_8080()
        proc = subprocess.Popen([compiled_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            wait_for_listener()
            assert receive_status() == EXPECTED, "A fresh build of restored server.c returned the wrong status"
        finally:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=2)
    finally:
        if os.path.exists(compiled_path):
            os.unlink(compiled_path)


def test_cron_txt_content():
    """Check that /home/user/cron.txt contains exactly one correct 5-minute schedule."""
    cron_path = "/home/user/cron.txt"
    assert os.path.isfile(cron_path), f"Cron file {cron_path} does not exist."
    with open(cron_path, "r") as f:
        content = f.read()

    lines = content.splitlines()
    assert len(lines) == 1, f"{cron_path} must contain exactly one line"
    pattern = r"\s*(?:\*/5|0,5,10,15,20,25,30,35,40,45,50,55)\s+\*\s+\*\s+\*\s+\*\s+/home/user/watchdog\.sh\s*"
    assert re.fullmatch(pattern, lines[0]), f"No valid 5-minute cron entry found for /home/user/watchdog.sh in {cron_path}"


def test_restore_status_log():
    """Check that the status log contains the exact success message."""
    log_path = "/home/user/restore_status.log"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist."
    with open(log_path, "rb") as f:
        content = f.read()
    assert content == EXPECTED, f"{log_path} does not contain the exact server output"


def test_watchdog_performs_supervision():
    stop_port_8080()
    real_server = SERVER_PATH + ".verifier-real"
    marker = f"/tmp/watchdog-invoked-{os.getpid()}"
    if os.path.exists(real_server):
        os.unlink(real_server)
    if os.path.exists(marker):
        os.unlink(marker)

    os.rename(SERVER_PATH, real_server)
    try:
        with open(SERVER_PATH, "w") as f:
            f.write(f"#!/bin/bash\necho invoked > {marker}\n")
        os.chmod(SERVER_PATH, 0o755)

        blocker = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        blocker.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        blocker.bind(("127.0.0.1", 8080))
        blocker.listen(1)
        try:
            run_watchdog()
            time.sleep(0.3)
            assert not os.path.exists(marker), "Watchdog started the server even though port 8080 was already open"
        finally:
            blocker.close()
    finally:
        if os.path.exists(SERVER_PATH):
            os.unlink(SERVER_PATH)
        os.rename(real_server, SERVER_PATH)
        if os.path.exists(marker):
            os.unlink(marker)

    stop_port_8080()
    run_watchdog()
    wait_for_listener()
    pids = listener_pids()
    assert pids, "Watchdog did not start a listener"
    expected_exe = os.path.realpath(SERVER_PATH)
    actual_exes = set()
    for pid in pids:
        try:
            actual_exes.add(os.path.realpath(f"/proc/{pid}/exe"))
        except (FileNotFoundError, PermissionError):
            pass
    assert expected_exe in actual_exes, "Watchdog did not start /home/user/restore/server"
    assert receive_status() == EXPECTED, "Server started by watchdog returned the wrong status"


def test_server_listening():
    """Check that the server is actively listening on 127.0.0.1:8080 and responds correctly."""
    try:
        data = receive_status()
        assert data == EXPECTED, "Server did not respond with the expected message."
    except ConnectionRefusedError:
        assert False, "Connection refused: Server is not listening on 127.0.0.1:8080."
    except socket.timeout:
        assert False, "Connection timed out: Server is not responding on 127.0.0.1:8080."
    except Exception as e:
        assert False, f"Failed to connect to server on 127.0.0.1:8080: {e}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
