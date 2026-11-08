#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import socket
import stat
import subprocess
import time
import urllib.error
import urllib.request

CONFIG = "/home/user/nginx/nginx.conf"
BACKUP_SCRIPT = "/home/user/backup.py"
BACKUP_FILE = "/home/user/backup/nginx.conf.bak"
SOCKET_FILE = "/home/user/app/app.sock"
MARKER = b"# BACKUP SUCCESSFUL"


def fetch():
    req = urllib.request.Request("http://localhost:8080", headers={"Connection": "close"})
    with urllib.request.urlopen(req, timeout=5) as response:
        return response.read().decode("utf-8")


def process_cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return f.read().replace(b"\0", b" ").decode("utf-8", "replace")
    except OSError:
        return ""


def process_exe(pid):
    try:
        return os.path.realpath(f"/proc/{pid}/exe")
    except OSError:
        return ""


def socket_owners(inode):
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
                except OSError:
                    pass
        except OSError:
            pass
    return owners


def listening_inodes(port):
    result = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if local.rsplit(":", 1)[1].upper() == wanted and state == "0A":
                        result.add(fields[9])
        except OSError:
            pass
    return result


def unix_socket_inode(path):
    with open("/proc/net/unix") as f:
        next(f)
        for line in f:
            fields = line.split()
            if len(fields) >= 8 and fields[7] == path:
                return fields[6]
    return None


def valid_backup(source, result):
    if not result.startswith(source):
        return False
    suffix = result[len(source):]
    return suffix in {
        MARKER,
        MARKER + b"\n",
        b"\n" + MARKER,
        b"\n" + MARKER + b"\n",
    }


def test_nginx_proxy_returns_hello_world():
    """Keep the original exact live-response assertion."""
    try:
        content = fetch()
        assert content == "Hello World\n", f"Expected 'Hello World\\n' but got '{content}'"
    except urllib.error.URLError as e:
        assert False, f"Failed to connect to http://localhost:8080: {e}. Is Nginx and the Python app running?"


def test_nginx_owns_port_and_uses_fixed_configuration():
    assert os.path.isfile(CONFIG), f"Nginx configuration {CONFIG} does not exist."
    with open(CONFIG, "r") as f:
        config = f.read()

    uncommented = "\n".join(line.split("#", 1)[0] for line in config.splitlines())
    assert re.search(r"proxy_pass\s+http://unix:/home/user/app/app\.sock\s*;", uncommented), \
        "The live Nginx configuration does not proxy to /home/user/app/app.sock."
    assert not re.search(r"proxy_pass\s+http://unix:/home/user/app/wrong\.sock\s*;", uncommented), \
        "The incorrect upstream socket is still active in the Nginx configuration."

    nginx = os.path.realpath(shutil.which("nginx") or "/usr/sbin/nginx")
    checked = subprocess.run(
        [nginx, "-t", "-c", CONFIG], stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, text=True, timeout=10
    )
    assert checked.returncode == 0, f"The fixed Nginx configuration is invalid:\n{checked.stdout}"

    inodes = listening_inodes(8080)
    assert inodes, "Nothing is listening on TCP port 8080."
    owners = {pid for inode in inodes for pid in socket_owners(inode)}
    assert owners, "Could not identify the process listening on TCP port 8080."
    assert any(process_exe(pid) == nginx for pid in owners), \
        "Port 8080 is not owned by the installed Nginx executable."
    assert any(
        process_exe(pid) == nginx and CONFIG in process_cmdline(pid)
        for pid in range(1, max([1] + [int(x) for x in os.listdir('/proc') if x.isdigit()]) + 1)
    ), "Nginx was not started with /home/user/nginx/nginx.conf."


def test_python_backend_is_running_and_nginx_depends_on_its_socket():
    assert os.path.exists(SOCKET_FILE), "The backend UNIX socket does not exist."
    assert stat.S_ISSOCK(os.stat(SOCKET_FILE).st_mode), f"{SOCKET_FILE} is not a UNIX socket."
    inode = unix_socket_inode(SOCKET_FILE)
    assert inode is not None, "The backend UNIX socket is not bound by a running process."
    owners = socket_owners(inode)
    assert any("/home/user/app/server.py" in process_cmdline(pid) for pid in owners), \
        "The UNIX socket is not owned by the required Python backend application."

    held = SOCKET_FILE + ".verifier-" + secrets.token_hex(8)
    os.rename(SOCKET_FILE, held)
    try:
        try:
            body = fetch()
            assert body != "Hello World\n", \
                "Nginx still returned the application response after its upstream socket was removed; it is not proxying to the required socket."
        except (urllib.error.URLError, TimeoutError, ConnectionError):
            pass
    finally:
        if os.path.lexists(held):
            if os.path.lexists(SOCKET_FILE):
                os.unlink(SOCKET_FILE)
            os.rename(held, SOCKET_FILE)

    last_error = None
    for _ in range(20):
        try:
            if fetch() == "Hello World\n":
                return
        except Exception as exc:
            last_error = exc
        time.sleep(0.25)
    assert False, f"Proxying did not recover after restoring the backend socket: {last_error}"


def test_backup_script_exists():
    """Keep the original script-existence assertion."""
    assert os.path.isfile(BACKUP_SCRIPT), "Backup script /home/user/backup.py does not exist."


def test_backup_file_exists_and_content():
    """Keep the original backup assertions and ensure it is a copy of the live config."""
    assert os.path.isfile(BACKUP_FILE), f"Backup file {BACKUP_FILE} does not exist."
    with open(BACKUP_FILE, "rb") as f:
        raw = f.read()
    with open(CONFIG, "rb") as f:
        source = f.read()
    content = raw.decode("utf-8")
    lines = content.splitlines()

    assert "proxy_pass http://unix:/home/user/app/app.sock;" in content, \
        "The backup file does not contain the fixed proxy_pass directive."
    assert len(lines) > 0, "The backup file is empty."
    assert lines[-1] == "# BACKUP SUCCESSFUL", \
        f"The last line of the backup file must be exactly '# BACKUP SUCCESSFUL', but got '{lines[-1]}'."
    assert valid_backup(source, raw), \
        "The backup is not an unchanged copy of the live Nginx configuration followed by the required marker."


def test_backup_script_performs_copy_and_append():
    """Execute backup.py against unpredictable source content and check its operation."""
    with open(CONFIG, "rb") as f:
        original_config = f.read()
    original_backup = None
    if os.path.exists(BACKUP_FILE):
        with open(BACKUP_FILE, "rb") as f:
            original_backup = f.read()

    probe = ("# verifier probe " + secrets.token_hex(24)).encode("ascii")
    try:
        with open(CONFIG, "wb") as f:
            f.write(probe)
        if os.path.lexists(BACKUP_FILE):
            os.unlink(BACKUP_FILE)

        result = subprocess.run(
            ["python3", BACKUP_SCRIPT], stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, text=True, timeout=10
        )
        assert result.returncode == 0, f"backup.py failed when executed:\n{result.stdout}"
        assert os.path.isfile(BACKUP_FILE), "backup.py did not create /home/user/backup/nginx.conf.bak."
        with open(BACKUP_FILE, "rb") as f:
            generated = f.read()
        assert valid_backup(probe, generated), \
            "backup.py did not copy the supplied configuration unchanged and append the required marker as the final line."
    finally:
        with open(CONFIG, "wb") as f:
            f.write(original_config)
        if original_backup is None:
            if os.path.lexists(BACKUP_FILE):
                os.unlink(BACKUP_FILE)
        else:
            with open(BACKUP_FILE, "wb") as f:
                f.write(original_backup)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
