#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import os
import secrets
import shutil
import socket
import ssl
import subprocess
import tempfile
import urllib.error
import urllib.request
from zoneinfo import ZoneInfo

ARCHIVE_DIR = "/home/user/archive_web"
TZ_SCRIPT = "/home/user/tz_rename.py"
SERVE_SCRIPT = "/home/user/serve.py"


def test_archive_web_directory_and_files():
    assert os.path.isdir(ARCHIVE_DIR), f"Directory {ARCHIVE_DIR} does not exist."

    expected_files = {
        "report_20230110_160000_UTC.dat": "Winter data\n",
        "report_20230715_213000_UTC.dat": "Summer data\n"
    }

    for filename, content in expected_files.items():
        filepath = os.path.join(ARCHIVE_DIR, filename)
        assert os.path.isfile(filepath), f"Expected file {filename} not found in {ARCHIVE_DIR}. Timezone conversion might be incorrect."
        with open(filepath, "r") as f:
            assert f.read() == content, f"Content of {filename} does not match expected data."


def test_timezone_script_exists_and_executes_on_derived_cases():
    assert os.path.isfile(TZ_SCRIPT), f"Required script {TZ_SCRIPT} does not exist."
    with open(TZ_SCRIPT, "rb") as f:
        compile(f.read(), TZ_SCRIPT, "exec")

    backup_dir = tempfile.mkdtemp(prefix="archive-verifier-backup-")
    original_entries = []
    try:
        for name in os.listdir(ARCHIVE_DIR):
            source = os.path.join(ARCHIVE_DIR, name)
            destination = os.path.join(backup_dir, name)
            os.replace(source, destination)
            original_entries.append(name)

        cases = {}
        while len(cases) < 4:
            local_dt = datetime.datetime(
                secrets.choice(range(2020, 2031)),
                secrets.choice(range(1, 13)),
                secrets.choice(range(10, 21)),
                secrets.choice(range(10, 19)),
                secrets.choice(range(0, 60)),
                secrets.choice(range(0, 60)),
            )
            source_name = local_dt.strftime("report_%Y%m%d_%H%M%S.dat")
            utc_dt = local_dt.replace(tzinfo=ZoneInfo("America/Los_Angeles")).astimezone(datetime.timezone.utc)
            expected_name = utc_dt.strftime("report_%Y%m%d_%H%M%S_UTC.dat")
            cases[source_name] = (expected_name, secrets.token_bytes(32))

        for source_name, (_, content) in cases.items():
            with open(os.path.join(ARCHIVE_DIR, source_name), "wb") as f:
                f.write(content)

        result = subprocess.run(
            ["python3", TZ_SCRIPT],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
        assert result.returncode == 0, f"tz_rename.py failed when executed:\nstdout: {result.stdout}\nstderr: {result.stderr}"

        assert set(os.listdir(ARCHIVE_DIR)) == {value[0] for value in cases.values()}, \
            "tz_rename.py did not rename exactly the dynamically generated report files."
        for source_name, (expected_name, expected_content) in cases.items():
            assert not os.path.exists(os.path.join(ARCHIVE_DIR, source_name)), f"Source file {source_name} was not renamed."
            with open(os.path.join(ARCHIVE_DIR, expected_name), "rb") as f:
                assert f.read() == expected_content, f"Renamed file {expected_name} did not preserve its content."
    finally:
        os.makedirs(ARCHIVE_DIR, exist_ok=True)
        for name in os.listdir(ARCHIVE_DIR):
            path = os.path.join(ARCHIVE_DIR, name)
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            else:
                os.unlink(path)
        for name in original_entries:
            os.replace(os.path.join(backup_dir, name), os.path.join(ARCHIVE_DIR, name))
        shutil.rmtree(backup_dir, ignore_errors=True)


def test_tls_certificate_and_key():
    cert_path = "/home/user/tls.crt"
    key_path = "/home/user/tls.key"

    assert os.path.isfile(cert_path), f"Certificate file {cert_path} does not exist."
    assert os.path.isfile(key_path), f"Key file {key_path} does not exist."

    try:
        subject_output = subprocess.check_output(
            ["openssl", "x509", "-in", cert_path, "-noout", "-subject"],
            text=True
        )
        assert "CN = migration.local" in subject_output, f"Certificate Common Name is incorrect: {subject_output}"
    except subprocess.CalledProcessError:
        assert False, "Failed to read certificate subject using openssl."

    cert_text = subprocess.check_output(
        ["openssl", "x509", "-in", cert_path, "-noout", "-text"], text=True
    ).lower()
    key_text = subprocess.check_output(
        ["openssl", "pkey", "-in", key_path, "-noout", "-text"], text=True
    ).lower()
    assert "id-ecpublickey" in cert_text, "Certificate does not contain an ECDSA public key."
    assert "prime256v1" in cert_text, "Certificate public key is not on the prime256v1 curve."
    assert "prime256v1" in key_text, "Private key is not on the prime256v1 curve."
    assert "ecdsa-with-" in cert_text, "Certificate is not signed using ECDSA."

    cert_pub = subprocess.check_output(["openssl", "x509", "-in", cert_path, "-pubkey", "-noout"])
    key_pub = subprocess.check_output(["openssl", "pkey", "-in", key_path, "-pubout"])
    assert cert_pub == key_pub, "TLS certificate and private key do not match."

    issuer = subprocess.check_output(["openssl", "x509", "-in", cert_path, "-noout", "-issuer"], text=True)
    subject = subprocess.check_output(["openssl", "x509", "-in", cert_path, "-noout", "-subject"], text=True)
    assert issuer.removeprefix("issuer=").strip() == subject.removeprefix("subject=").strip(), "Certificate is not self-signed."
    subprocess.check_call(["openssl", "verify", "-CAfile", cert_path, cert_path], stdout=subprocess.DEVNULL)

    dates = subprocess.check_output(["openssl", "x509", "-in", cert_path, "-noout", "-dates"], text=True)
    values = dict(line.strip().split("=", 1) for line in dates.splitlines())
    parse = lambda value: datetime.datetime.strptime(value, "%b %d %H:%M:%S %Y %Z").replace(tzinfo=datetime.timezone.utc)
    not_before = parse(values["notBefore"])
    not_after = parse(values["notAfter"])
    now = datetime.datetime.now(datetime.timezone.utc)
    assert not_after - not_before == datetime.timedelta(days=30), "Certificate validity period is not exactly 30 days."
    assert not_before <= now <= not_after, "Certificate is not currently valid."


def test_server_pid():
    assert os.path.isfile(SERVE_SCRIPT), f"Required script {SERVE_SCRIPT} does not exist."
    with open(SERVE_SCRIPT, "rb") as f:
        compile(f.read(), SERVE_SCRIPT, "exec")

    pid_file = "/home/user/server.pid"
    assert os.path.isfile(pid_file), f"PID file {pid_file} does not exist."

    with open(pid_file, "r") as f:
        pid_str = f.read().strip()

    assert pid_str.isdigit(), f"PID file does not contain a valid integer: {pid_str}"
    pid = int(pid_str)

    try:
        os.kill(pid, 0)
    except OSError:
        assert False, f"Process with PID {pid} is not running."

    with open(f"/proc/{pid}/cmdline", "rb") as f:
        argv = [part.decode(errors="replace") for part in f.read().split(b"\0") if part]
    process_cwd = os.readlink(f"/proc/{pid}/cwd")
    invoked_paths = {
        os.path.realpath(arg if os.path.isabs(arg) else os.path.join(process_cwd, arg))
        for arg in argv
        if arg and not arg.startswith("-")
    }
    assert os.path.realpath(SERVE_SCRIPT) in invoked_paths, "The PID does not belong to a process executing serve.py."

    socket_inodes = set()
    for fd in os.listdir(f"/proc/{pid}/fd"):
        try:
            target = os.readlink(f"/proc/{pid}/fd/{fd}")
        except OSError:
            continue
        if target.startswith("socket:[") and target.endswith("]"):
            socket_inodes.add(target[8:-1])

    listening = False
    with open("/proc/net/tcp", "r") as f:
        next(f)
        for line in f:
            fields = line.split()
            local_address, state, inode = fields[1], fields[3], fields[9]
            if local_address == "00000000:20FB" and state == "0A" and inode in socket_inodes:
                listening = True
                break
    assert listening, "The PID process is not listening on 0.0.0.0:8443."


def test_https_web_server():
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    with socket.create_connection(("localhost", 8443), timeout=5) as raw_socket:
        with ctx.wrap_socket(raw_socket, server_hostname="migration.local") as tls_socket:
            served_der = tls_socket.getpeercert(binary_form=True)
    with open("/home/user/tls.crt", "r") as f:
        expected_der = ssl.PEM_cert_to_DER_cert(f.read())
    assert served_der == expected_der, "HTTPS server is not using /home/user/tls.crt."

    expected_files = {
        "report_20230110_160000_UTC.dat": b"Winter data\n",
        "report_20230715_213000_UTC.dat": b"Summer data\n"
    }

    for filename, expected_content in expected_files.items():
        url = f"https://localhost:8443/{filename}"
        try:
            with urllib.request.urlopen(url, context=ctx, timeout=5) as response:
                assert response.status == 200, f"Failed to fetch {filename}, HTTP status {response.status}"
                content = response.read()
                assert content == expected_content, f"Served content for {filename} does not match expected data."
        except urllib.error.URLError as e:
            assert False, f"Failed to connect to HTTPS server on port 8443 or fetch {filename}: {e}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
