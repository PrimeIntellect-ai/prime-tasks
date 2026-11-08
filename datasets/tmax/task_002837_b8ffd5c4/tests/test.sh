#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import socket
import stat
import subprocess
import tarfile
import tempfile
import time
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import PurePosixPath
import secrets
import pytest

try:
    import zoneinfo
except ImportError:
    zoneinfo = None


def _live_pid(pid):
    try:
        with open(f"/proc/{pid}/stat", "r") as f:
            fields = f.read().split()
        return len(fields) > 2 and fields[2] != "Z"
    except (OSError, ValueError):
        return False


def _cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return f.read().replace(b"\0", b" ").decode("utf-8", "replace")
    except OSError:
        return ""


def _listener_inodes(port):
    result = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) < 10:
                        continue
                    local = fields[1]
                    state = fields[3]
                    if state == "0A" and int(local.rsplit(":", 1)[1], 16) == port:
                        result.add(fields[9])
        except OSError:
            pass
    return result


def _pids_owning_inodes(inodes):
    owners = set()
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
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    owners.add(int(entry))
        except OSError:
            continue
    return owners


def _unix_http_get(socket_path):
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(5)
    try:
        client.connect(socket_path)
        client.sendall(b"GET / HTTP/1.0\r\nHost: localhost\r\nConnection: close\r\n\r\n")
        chunks = []
        while True:
            data = client.recv(65536)
            if not data:
                break
            chunks.append(data)
    finally:
        client.close()
    response = b"".join(chunks)
    head, separator, body = response.partition(b"\r\n\r\n")
    assert separator, "Application did not return a valid HTTP response over its Unix socket."
    assert head.splitlines()[0].split()[1] == b"200", f"Application Unix socket response was not 200: {head!r}"
    assert body.strip() == b"Success", f"Unexpected direct application response: {body!r}"


def test_web_service_success():
    """Verify the wrapper starts Nginx and the Python app on one matching Unix socket."""
    start_script = "/home/user/service/start.sh"
    nginx_config = "/home/user/service/nginx.conf"
    assert os.path.isfile(start_script), f"Missing service wrapper {start_script}."
    assert os.access(start_script, os.X_OK), f"Service wrapper {start_script} is not executable."
    assert os.path.isfile(nginx_config), f"Missing Nginx configuration {nginx_config}."

    with open(nginx_config, "r") as f:
        config = f.read()
    matches = re.findall(r"proxy_pass\s+http://unix:([^;\s]+)\s*;", config)
    assert matches, "Nginx configuration has no static Unix-socket proxy_pass target."
    socket_path = matches[0]
    if socket_path.endswith(":"):
        socket_path = socket_path[:-1]
    assert socket_path.startswith("/"), "Nginx Unix socket target must be an absolute path."

    result = subprocess.run(
        [start_script, "restart"],
        cwd="/home/user/service",
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=15,
    )
    assert result.returncode == 0, "The provided service wrapper failed to restart the service."

    deadline = time.time() + 8
    last_error = None
    while time.time() < deadline:
        try:
            if stat.S_ISSOCK(os.stat(socket_path).st_mode):
                with urllib.request.urlopen("http://127.0.0.1:8080", timeout=1) as req:
                    if req.getcode() == 200 and req.read().decode("utf-8").strip() == "Success":
                        break
        except Exception as exc:
            last_error = exc
        time.sleep(0.2)
    else:
        pytest.fail(f"Service did not become healthy after restart: {last_error}")

    for pid_name, required_text in (("app.pid", "app.py"), ("nginx.pid", "nginx")):
        pid_path = os.path.join("/home/user/service", pid_name)
        assert os.path.isfile(pid_path), f"Service restart did not create {pid_path}."
        with open(pid_path, "r") as f:
            pid = int(f.read().strip())
        assert _live_pid(pid), f"Process recorded in {pid_name} is not running."
        assert required_text in _cmdline(pid), f"Process in {pid_name} is not the required {required_text} process."
        if pid_name == "app.pid":
            assert socket_path in _cmdline(pid), "The Python application was not started with Nginx's Unix socket path."

    assert stat.S_ISSOCK(os.stat(socket_path).st_mode), f"{socket_path} is not a Unix socket."
    _unix_http_get(socket_path)

    listener_pids = _pids_owning_inodes(_listener_inodes(8080))
    assert listener_pids, "No process is listening on port 8080."
    assert any("nginx" in _cmdline(pid) for pid in listener_pids), "Port 8080 is not being served by Nginx."

    url = "http://127.0.0.1:8080"
    try:
        req = urllib.request.urlopen(url, timeout=5)
        status_code = req.getcode()
        content = req.read().decode("utf-8").strip()
        assert status_code == 200, f"Expected status code 200, got {status_code}"
        assert content == "Success", f"Expected response body 'Success', got '{content}'"
    except urllib.error.HTTPError as e:
        pytest.fail(f"Service returned an HTTP error: {e.code} {e.reason}. The Nginx/Python socket configuration is likely still incorrect.")
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to {url}: {e.reason}. Ensure both Nginx and the Python app are running.")
    except Exception as e:
        pytest.fail(f"Unexpected error when testing the web service: {e}")


def test_acl_permissions():
    """Verify that nobody has a named r-x ACL and ownership was not changed."""
    target_dir = "/home/user/service/public"
    assert os.path.exists(target_dir), f"Directory {target_dir} does not exist."
    info = os.stat(target_dir)
    assert info.st_uid == 0 and info.st_gid == 0, "The standard owner or group of the public directory was changed."
    try:
        out = subprocess.check_output(["getfacl", target_dir], text=True, stderr=subprocess.STDOUT)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to execute getfacl on {target_dir}: {e.output}")
    assert "user:nobody:r-x" in out, "ACL for user 'nobody' is not set to 'r-x' (read and execute) on the target directory."


def test_backup_archive():
    """Verify the compressed backup contains the original files and bytes."""
    archive_path = "/home/user/legacy_data_backup.tar.gz"
    assert os.path.exists(archive_path), f"Backup archive {archive_path} does not exist."
    assert tarfile.is_tarfile(archive_path), f"File {archive_path} is not a valid tar archive."
    expected = {"file1.txt": b"data1\n", "file2.txt": b"data2\n"}
    with tarfile.open(archive_path, "r:gz") as tar:
        names = tar.getnames()
        assert any("file1.txt" in name for name in names), "file1.txt is missing from the backup archive."
        assert any("file2.txt" in name for name in names), "file2.txt is missing from the backup archive."
        for filename, expected_bytes in expected.items():
            matches = [m for m in tar.getmembers() if PurePosixPath(m.name).name == filename]
            assert len(matches) == 1, f"Expected exactly one archived {filename}."
            assert matches[0].isfile(), f"Archived {filename} is not a regular file."
            extracted = tar.extractfile(matches[0])
            assert extracted is not None and extracted.read() == expected_bytes, f"Archived {filename} has incorrect contents."


def _run_storage_script(script, forced_free=None):
    status_file = "/home/user/storage_status.txt"
    try:
        os.remove(status_file)
    except FileNotFoundError:
        pass
    env = os.environ.copy()
    temp_dir = None
    if forced_free is not None:
        temp_dir = tempfile.TemporaryDirectory()
        with open(os.path.join(temp_dir.name, "sitecustomize.py"), "w") as f:
            f.write(
                "import os, shutil\n"
                "free = int(os.environ['VERIFIER_FORCED_FREE'])\n"
                "shutil.disk_usage = lambda path: shutil._ntuple_diskusage(free + 2097152, 2097152, free)\n"
                "class V:\n"
                "    f_bsize=4096; f_frsize=4096; f_blocks=1000000; f_bfree=0; f_files=1; f_ffree=1; f_favail=1; f_flag=0; f_namemax=255\n"
                "    f_bavail=free // 4096\n"
                "os.statvfs = lambda path: V()\n"
            )
        env["VERIFIER_FORCED_FREE"] = str(forced_free)
        env["PYTHONPATH"] = temp_dir.name + (os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
    try:
        result = subprocess.run(["python3", script], cwd="/home/user", env=env, timeout=15)
    finally:
        if temp_dir is not None:
            temp_dir.cleanup()
    assert result.returncode == 0, "storage_check.py did not execute successfully."
    assert os.path.isfile(status_file), "storage_check.py did not create /home/user/storage_status.txt."
    with open(status_file, "r") as f:
        return f.read().strip()


def test_storage_status():
    """Execute the storage script and exercise both sides of the threshold."""
    script = "/home/user/storage_check.py"
    assert os.path.isfile(script) and not os.path.islink(script), f"Storage monitoring script {script} is missing or invalid."
    assert _run_storage_script(script, 1048577) == "OK", "storage_check.py did not report OK above the threshold."
    assert _run_storage_script(script, 1048576) == "FULL", "storage_check.py did not report FULL at the threshold."

    actual_status = _run_storage_script(script)
    free_space = shutil.disk_usage("/").free
    expected_status = "OK" if free_space > 1048576 else "FULL"
    assert actual_status == expected_status, f"Expected storage status '{expected_status}' based on current free space, but got '{actual_status}'."


def _expected_conversions(lines):
    assert zoneinfo is not None, "Python zoneinfo support is required for verification."
    converted = []
    for line in lines:
        dt = datetime.strptime(line, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=zoneinfo.ZoneInfo("UTC"))
        converted.append(dt.astimezone(zoneinfo.ZoneInfo("America/New_York")).strftime("%Y-%m-%d %H:%M:%S"))
    return converted


def _run_timezone_script(script):
    output_file = "/home/user/events_ny.log"
    try:
        os.remove(output_file)
    except FileNotFoundError:
        pass
    result = subprocess.run(["python3", script], cwd="/home/user", timeout=15)
    assert result.returncode == 0, "tz_convert.py did not execute successfully."
    assert os.path.isfile(output_file), f"Converted log file {output_file} does not exist."
    with open(output_file, "r") as f:
        return [line.strip() for line in f if line.strip()]


def test_timezone_conversion():
    """Execute the converter on verifier-generated timestamps, then regenerate the requested output."""
    script = "/home/user/tz_convert.py"
    input_file = "/home/user/events.log"
    assert os.path.isfile(script) and not os.path.islink(script), f"Timezone conversion script {script} is missing or invalid."
    assert os.path.isfile(input_file), f"Input log file {input_file} does not exist."

    with open(input_file, "rb") as f:
        original = f.read()
    base = datetime(2020, 1, 1, tzinfo=timezone.utc) + timedelta(seconds=secrets.randbelow(6 * 365 * 24 * 3600))
    generated = [(base + timedelta(seconds=i * 93847)).strftime("%Y-%m-%dT%H:%M:%SZ") for i in range(5)]
    try:
        with open(input_file, "w") as f:
            f.write("\n".join(generated) + "\n")
        assert _run_timezone_script(script) == _expected_conversions(generated), "tz_convert.py failed on verifier-generated UTC timestamps."
    finally:
        with open(input_file, "wb") as f:
            f.write(original)

    actual_lines = _run_timezone_script(script)
    source_lines = [line.strip() for line in original.decode("utf-8").splitlines() if line.strip()]
    expected_lines = _expected_conversions(source_lines)
    assert actual_lines == expected_lines, f"Converted timestamps in /home/user/events_ny.log do not match the expected America/New_York values."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
