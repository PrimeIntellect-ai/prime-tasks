#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import hashlib
import json
import os
import re
import ssl
import subprocess
import tarfile
import urllib.error
import urllib.request
import pytest

DATA_DIR = "/home/user/data_dir"
BACKUP = "/home/user/backup_dir/data_backup.tar.gz"
ALERT = "ALERT: data_dir exceeds 50MB"


def source_files():
    result = {}
    for root, _, files in os.walk(DATA_DIR):
        for name in files:
            path = os.path.join(root, name)
            rel = os.path.relpath(path, DATA_DIR)
            with open(path, "rb") as f:
                result[rel] = (os.path.getsize(path), hashlib.sha256(f.read()).hexdigest())
    return result


def archive_files(path):
    result = {}
    with tarfile.open(path, "r:gz") as tar:
        names = tar.getnames()
        assert any("large_file.dat" in name for name in names), "Backup does not contain the expected data files."
        for member in tar.getmembers():
            if not member.isfile():
                continue
            parts = [p for p in member.name.lstrip("/").split("/") if p not in ("", ".")]
            assert "data_dir" in parts, f"Archive member is outside data_dir: {member.name}"
            rel_parts = parts[parts.index("data_dir") + 1:]
            assert rel_parts, f"Invalid archive member path: {member.name}"
            rel = os.path.join(*rel_parts)
            extracted = tar.extractfile(member)
            assert extracted is not None
            digest = hashlib.sha256(extracted.read()).hexdigest()
            assert rel not in result, f"Duplicate archive entry for {rel}"
            result[rel] = (member.size, digest)
    return result


def test_scripts_exist():
    bash_script = "/home/user/setup_and_run.sh"
    python_script = "/home/user/monitor.py"
    assert os.path.isfile(bash_script), f"Deployment script {bash_script} is missing."
    assert os.access(bash_script, os.X_OK), f"Deployment script {bash_script} is not executable."
    assert os.path.isfile(python_script), f"Python daemon {python_script} is missing."


def test_certs_exist_and_are_correct():
    cert_path = "/home/user/certs/cert.pem"
    key_path = "/home/user/certs/key.pem"
    assert os.path.isfile(cert_path), f"Certificate file {cert_path} is missing."
    assert os.path.isfile(key_path), f"Private key file {key_path} is missing."

    text = subprocess.check_output(["openssl", "x509", "-in", cert_path, "-noout", "-text"], text=True)
    assert "Public-Key: (2048 bit)" in text, "Certificate does not contain a 2048-bit RSA key."
    subject = subprocess.check_output(
        ["openssl", "x509", "-in", cert_path, "-noout", "-subject", "-nameopt", "RFC2253"], text=True
    ).strip()
    assert re.search(r"(?:^|,)CN=localhost(?:,|$)", subject.removeprefix("subject=")), "Certificate CN is not localhost."

    dates = subprocess.check_output(["openssl", "x509", "-in", cert_path, "-noout", "-dates"], text=True).splitlines()
    values = dict(line.split("=", 1) for line in dates)
    fmt = "%b %d %H:%M:%S %Y %Z"
    start = datetime.datetime.strptime(values["notBefore"], fmt)
    end = datetime.datetime.strptime(values["notAfter"], fmt)
    lifetime = (end - start).total_seconds()
    assert 29.9 * 86400 <= lifetime <= 30.1 * 86400, "Certificate is not valid for 30 days."

    cert_pub = subprocess.check_output(["openssl", "x509", "-in", cert_path, "-pubkey", "-noout"])
    cert_der = subprocess.check_output(["openssl", "pkey", "-pubin", "-outform", "DER"], input=cert_pub)
    key_der = subprocess.check_output(["openssl", "pkey", "-in", key_path, "-pubout", "-outform", "DER"])
    assert cert_der == key_der, "Certificate and private key do not match."


def test_backup_created():
    assert os.path.isfile(BACKUP), f"Backup file {BACKUP} was not created."
    try:
        actual = archive_files(BACKUP)
    except tarfile.TarError:
        pytest.fail(f"Backup file {BACKUP} is not a valid gzip-compressed tarball.")
    assert actual == source_files(), "Backup contents do not exactly match data_dir."


def test_alert_logged():
    log_path = "/home/user/alerts.log"
    assert os.path.isfile(log_path), f"Log file {log_path} is missing."
    with open(log_path, "r") as f:
        content = f.read()
    assert ALERT in content, f"Expected alert string not found in {log_path}."
    assert all(line == ALERT for line in content.splitlines()), "alerts.log contains an invalid alert line."


def test_pid_file_and_process_running():
    pid_file = "/home/user/monitor.pid"
    assert os.path.isfile(pid_file), f"PID file {pid_file} is missing."
    with open(pid_file, "r") as f:
        pid_str = f.read().strip()
    assert pid_str.isdigit(), f"PID file {pid_file} does not contain a valid numeric PID."
    pid = int(pid_str)
    try:
        os.kill(pid, 0)
    except OSError:
        pytest.fail(f"Process with PID {pid} from {pid_file} is not running.")
    with open(f"/proc/{pid}/cmdline", "rb") as f:
        cmdline = f.read().replace(b"\0", b" ").decode(errors="replace")
    assert "monitor.py" in cmdline, "PID file does not identify the monitoring daemon."


def test_https_server_response():
    url = "https://127.0.0.1:8443/status"
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    try:
        req = urllib.request.Request(url, method="GET")
        with urllib.request.urlopen(req, context=ctx, timeout=5) as response:
            assert response.status == 200, f"Expected HTTP 200, got {response.status}"
            data = response.read().decode("utf-8")
            try:
                json_data = json.loads(data)
            except json.JSONDecodeError:
                pytest.fail("Server response is not valid JSON.")
            assert json_data.get("disk_status") == "ALERT", "Expected 'disk_status' to be 'ALERT'."
            assert json_data.get("backup_path") == BACKUP, "Incorrect 'backup_path' in JSON response."
            assert json_data == {"disk_status": "ALERT", "backup_path": BACKUP}, "Status JSON contains incorrect or extra fields."
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to the HTTPS server at {url}: {e}")
TEST_EOF

cat << 'DYNAMIC_EOF' > /tmp/test_dynamic_behavior.py
import json
import os
import shutil
import signal
import ssl
import subprocess
import tarfile
import time
import urllib.request

HOME = "/home/user"
DATA = HOME + "/data_dir"
BACKUP_DIR = HOME + "/backup_dir"
BACKUP = BACKUP_DIR + "/data_backup.tar.gz"
LOG = HOME + "/alerts.log"
PIDFILE = HOME + "/monitor.pid"
EXPECTED_ALERT = "ALERT: data_dir exceeds 50MB\n"


def listener_pids():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[1].split(":")[-1].upper() == "20FB" and fields[3] == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass
    pids = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == os.getpid():
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
        except OSError:
            pass
    return pids


def stop_server():
    pids = set(listener_pids())
    try:
        with open(PIDFILE) as f:
            value = f.read().strip()
        if value.isdigit():
            pids.add(int(value))
    except OSError:
        pass
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except OSError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and listener_pids():
        time.sleep(0.05)
    for pid in listener_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except OSError:
            pass
    time.sleep(0.2)


def status():
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    last = None
    for _ in range(100):
        try:
            with urllib.request.urlopen("https://127.0.0.1:8443/status", context=ctx, timeout=1) as response:
                assert response.status == 200
                return json.loads(response.read().decode("utf-8"))
        except Exception as exc:
            last = exc
            time.sleep(0.1)
    raise AssertionError(f"Daemon did not start: {last}")


def launch():
    subprocess.run([HOME + "/setup_and_run.sh"], check=True, timeout=15,
                   stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    with open(PIDFILE) as f:
        value = f.read().strip()
    assert value.isdigit()
    pid = int(value)
    os.kill(pid, 0)
    with open(f"/proc/{pid}/cmdline", "rb") as f:
        assert b"monitor.py" in f.read()
    return status()


def archived_files():
    result = {}
    with tarfile.open(BACKUP, "r:gz") as tar:
        for member in tar.getmembers():
            if not member.isfile():
                continue
            parts = [p for p in member.name.lstrip("/").split("/") if p not in ("", ".")]
            assert "data_dir" in parts
            rel = "/".join(parts[parts.index("data_dir") + 1:])
            assert rel and rel not in result
            stream = tar.extractfile(member)
            result[rel] = stream.read() if stream else None
    return result


def test_boundary_and_over_quota_behavior_via_deployment_script():
    stop_server()
    sandbox = "/tmp/verifier_saved_state"
    shutil.rmtree(sandbox, ignore_errors=True)
    os.makedirs(sandbox)
    for path in (DATA, BACKUP_DIR, HOME + "/certs", LOG, PIDFILE):
        if os.path.lexists(path):
            shutil.move(path, os.path.join(sandbox, os.path.basename(path)))

    try:
        os.makedirs(os.path.join(DATA, "nested"))
        # Total is exactly 50,000,000 bytes; the requirement says this is still OK.
        with open(os.path.join(DATA, "small.bin"), "wb") as f:
            f.write(b"0123456789")
        os.truncate(os.path.join(DATA, "nested", "bulk.bin"), 49_999_990)

        result = launch()
        assert result == {"disk_status": "OK", "backup_path": None}
        assert not os.path.exists(BACKUP), "Backup was incorrectly created at the exact threshold."
        assert not os.path.exists(LOG), "Alert was incorrectly logged at the exact threshold."
        stop_server()

        # Derive the over-quota case by adding one byte to the same nested data set.
        with open(os.path.join(DATA, "small.bin"), "ab") as f:
            f.write(b"X")
        result = launch()
        assert result == {"disk_status": "ALERT", "backup_path": BACKUP}
        assert os.path.isfile(BACKUP)
        with open(LOG, "rb") as f:
            assert f.read() == EXPECTED_ALERT.encode(), "Daemon did not append exactly the required alert line."

        files = archived_files()
        assert set(files) == {"small.bin", "nested/bulk.bin"}, "Backup does not exactly contain the monitored files."
        assert files["small.bin"] == b"0123456789X"
        assert files["nested/bulk.bin"] == b"\0" * 49_999_990
    finally:
        stop_server()
DYNAMIC_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 && \
   python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_dynamic_behavior.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
