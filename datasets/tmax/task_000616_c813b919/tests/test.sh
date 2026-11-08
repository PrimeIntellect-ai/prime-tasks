#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import glob
import json
import os
import secrets
import shlex
import signal
import socket
import stat
import subprocess
import tarfile
import tempfile
import time
from email import policy
from email.parser import BytesParser

import pytest

CAPTURE_FILE = "/tmp/smtp_capture.jsonl"


def stop_original_smtp():
    for proc in glob.glob("/proc/[0-9]*/cmdline"):
        try:
            with open(proc, "rb") as f:
                cmdline = f.read()
            if b"/app/smtp_mock.py" in cmdline:
                os.kill(int(proc.split("/")[2]), signal.SIGTERM)
        except (FileNotFoundError, ProcessLookupError, PermissionError, ValueError):
            pass
    time.sleep(0.5)


@pytest.fixture(scope="session", autouse=True)
def smtp_capture_server():
    stop_original_smtp()
    try:
        os.unlink(CAPTURE_FILE)
    except FileNotFoundError:
        pass

    capture_program = r'''
import asyncore
import base64
import json
import smtpd

OUT = "/tmp/smtp_capture.jsonl"

class CaptureServer(smtpd.SMTPServer):
    def process_message(self, peer, mailfrom, rcpttos, data, **kwargs):
        record = {
            "mailfrom": mailfrom,
            "rcpttos": list(rcpttos),
            "data": base64.b64encode(data).decode("ascii"),
        }
        with open(OUT, "a", encoding="utf-8") as f:
            f.write(json.dumps(record) + "\n")
            f.flush()

CaptureServer(("127.0.0.1", 2525), None)
asyncore.loop()
'''
    capture_script = "/tmp/smtp_capture_server.py"
    with open(capture_script, "w") as f:
        f.write(capture_program)
    proc = subprocess.Popen(
        ["python3", capture_script],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
    )

    ready = False
    for _ in range(50):
        if proc.poll() is not None:
            break
        try:
            with socket.create_connection(("127.0.0.1", 2525), timeout=0.2):
                ready = True
                break
        except OSError:
            time.sleep(0.1)
    if not ready:
        stderr = proc.stderr.read() if proc.poll() is not None else ""
        proc.terminate()
        pytest.fail(f"Could not start SMTP capture server: {stderr}")

    yield
    proc.terminate()
    try:
        proc.wait(timeout=3)
    except subprocess.TimeoutExpired:
        proc.kill()


def passwd_entries():
    entries = {}
    with open("/app/passwd", encoding="utf-8") as f:
        for line in f:
            fields = line.rstrip("\n").split(":")
            if len(fields) >= 7:
                entries[fields[0]] = fields[5]
    return entries


def test_generate_report():
    """Verify exact reports for existing and unpredictable passwd entries."""
    script_path = "/app/generate_report.sh"
    assert os.path.isfile(script_path), f"{script_path} is missing."
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable."

    original_passwd = open("/app/passwd", "rb").read()
    username = "verify_" + secrets.token_hex(6)
    homedir = "/srv/home/" + secrets.token_hex(8)
    try:
        with open("/app/passwd", "ab") as f:
            if original_passwd and not original_passwd.endswith(b"\n"):
                f.write(b"\n")
            f.write(f"{username}:x:24001:24001:Verifier User:{homedir}:/bin/sh\n".encode())

        entries = passwd_entries()
        assert username in entries
        for user, home in entries.items():
            try:
                output = subprocess.check_output(
                    [script_path, user], text=True, stderr=subprocess.STDOUT, timeout=5
                )
            except subprocess.CalledProcessError as e:
                pytest.fail(f"{script_path} failed with exit code {e.returncode} and output: {e.output}")
            expected = f"User {user} has home {home}\n"
            assert output == expected, f"Expected exact output {expected!r}, got {output!r}"
    finally:
        with open("/app/passwd", "wb") as f:
            f.write(original_passwd)


def test_cron_backup():
    """Execute the backup script in a restricted environment and validate its archive."""
    script_path = "/app/cron_backup.sh"
    backup_dir = "/app/backups"
    assert os.path.isfile(script_path), f"{script_path} is missing."
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable."
    os.makedirs(backup_dir, exist_ok=True)

    original_passwd = open("/app/passwd", "rb").read()
    marker_user = "backupcheck_" + secrets.token_hex(8)
    try:
        with open("/app/passwd", "ab") as f:
            if original_passwd and not original_passwd.endswith(b"\n"):
                f.write(b"\n")
            f.write(f"{marker_user}:x:25001:25001:Backup Check:/home/{marker_user}:/bin/false\n".encode())
        expected_passwd = open("/app/passwd", "rb").read()

        before = {
            p: os.stat(p).st_mtime_ns
            for p in glob.glob(os.path.join(backup_dir, "backup_*.tar.gz"))
        }
        result = subprocess.run(
            [script_path],
            env={"PATH": "/nonexistent", "BACKUP_DIR": "/tmp/incorrect_backup_destination"},
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        assert result.returncode == 0, (
            f"cron_backup.sh failed in a restricted environment: {result.stderr}"
        )

        backups = glob.glob(os.path.join(backup_dir, "backup_*.tar.gz"))
        assert backups, f"No backup_*.tar.gz files found in {backup_dir}."
        changed = [
            p for p in backups
            if p not in before or os.stat(p).st_mtime_ns != before[p]
        ]
        assert changed, "Running cron_backup.sh did not create or update a backup in /app/backups/."

        valid = False
        errors = []
        for archive in changed:
            try:
                with tarfile.open(archive, "r:gz") as tf:
                    members = [m for m in tf.getmembers() if m.name.lstrip("./") == "app/passwd"]
                    if len(members) != 1 or not members[0].isfile():
                        continue
                    extracted = tf.extractfile(members[0])
                    if extracted is not None and extracted.read() == expected_passwd:
                        valid = True
                        break
            except (tarfile.TarError, OSError) as e:
                errors.append(f"{archive}: {e}")
        assert valid, "No newly produced gzip tar archive contained the current /app/passwd: " + "; ".join(errors)
    finally:
        with open("/app/passwd", "wb") as f:
            f.write(original_passwd)


def test_rotate_logs():
    """Verify that rotate_logs.sh correctly rotates and recreates the log file."""
    script_path = "/app/rotate_logs.sh"
    assert os.path.isfile(script_path), f"{script_path} is missing."
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable."

    test_log = "/app/test_rotation.log"
    test_log_rotated = test_log + ".1"
    with open(test_log, "w") as f:
        f.write("test log content")

    try:
        subprocess.check_call([script_path, test_log])
    except subprocess.CalledProcessError:
        pytest.fail(f"{script_path} failed during execution.")

    assert os.path.isfile(test_log_rotated), f"Rotated log file {test_log_rotated} was not created."
    with open(test_log_rotated) as f:
        content = f.read()
    assert content == "test log content", "Rotated log file does not contain the original content."
    assert os.path.isfile(test_log), f"New log file {test_log} was not created."
    assert os.path.getsize(test_log) == 0, f"New log file {test_log} is not empty."
    perms = stat.S_IMODE(os.stat(test_log).st_mode)
    assert perms == 0o644, f"New log file has incorrect permissions: {oct(perms)}, expected 0o644."


def read_capture_records():
    records = []
    try:
        with open(CAPTURE_FILE, encoding="utf-8") as f:
            for line in f:
                try:
                    records.append(json.loads(line))
                except json.JSONDecodeError:
                    pass
    except FileNotFoundError:
        pass
    return records


def smtp_body(data):
    message = BytesParser(policy=policy.default).parsebytes(data)
    assert not message.is_multipart(), "Report email unexpectedly used a multipart body."
    payload = message.get_payload(decode=True)
    if payload is None:
        raw = message.get_payload()
        assert isinstance(raw, str)
        return raw
    charset = message.get_content_charset() or "utf-8"
    return payload.decode(charset)


def test_account_daemon():
    """Exercise the compiled daemon with an unpredictable user and inspect SMTP envelope/body."""
    daemon_path = "/app/account_daemon"
    source_path = "/app/account_daemon.c"
    assert os.path.isfile(source_path), f"{source_path} is missing."
    assert os.path.isfile(daemon_path), f"{daemon_path} is missing."
    assert os.access(daemon_path, os.X_OK), f"{daemon_path} is not executable."
    with open(daemon_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{daemon_path} is not a compiled ELF executable."

    report_path = "/app/generate_report.sh"
    original_report = open(report_path, "rb").read()
    original_mode = stat.S_IMODE(os.stat(report_path).st_mode)
    original_passwd = open("/app/passwd", "rb").read()
    username = "daemoncheck_" + secrets.token_hex(7)
    homedir = "/opt/accounts/" + secrets.token_hex(9)
    expected = f"User {username} has home {homedir}"

    fd, saved_report = tempfile.mkstemp(prefix="saved_report_", suffix=".sh")
    os.close(fd)
    with open(saved_report, "wb") as f:
        f.write(original_report)
    os.chmod(saved_report, original_mode | 0o100)
    probe = "/tmp/report_probe_" + secrets.token_hex(8)

    try:
        with open("/app/passwd", "ab") as f:
            if original_passwd and not original_passwd.endswith(b"\n"):
                f.write(b"\n")
            f.write(f"{username}:x:26001:26001:Daemon Check:{homedir}:/bin/sh\n".encode())

        wrapper = (
            "#!/bin/bash\n"
            f"printf '%s\\n' \"$1\" >> {shlex.quote(probe)}\n"
            f"exec {shlex.quote(saved_report)} \"$@\"\n"
        )
        with open(report_path, "w") as f:
            f.write(wrapper)
        os.chmod(report_path, 0o755)

        before_count = len(read_capture_records())
        try:
            with socket.create_connection(("127.0.0.1", 8888), timeout=5) as s:
                s.sendall(f"REPORT {username}\n".encode())
        except Exception as e:
            pytest.fail(f"Failed to connect and send data to daemon on port 8888: {e}")

        matching = None
        for _ in range(50):
            records = read_capture_records()[before_count:]
            for record in records:
                data = base64.b64decode(record["data"])
                try:
                    body = smtp_body(data).replace("\r\n", "\n")
                except Exception:
                    continue
                if body in (expected, expected + "\n"):
                    matching = record
                    break
            if matching is not None:
                break
            time.sleep(0.2)

        assert matching is not None, f"No new email had the exact report body {expected!r}."
        assert matching["mailfrom"] == "daemon@local.site", (
            f"Wrong SMTP envelope sender: {matching['mailfrom']!r}"
        )
        assert matching["rcpttos"] == ["admin@local.site"], (
            f"Wrong SMTP envelope recipients: {matching['rcpttos']!r}"
        )
        assert os.path.isfile(probe), "The daemon did not invoke /app/generate_report.sh."
        with open(probe) as f:
            invocations = [line.rstrip("\n") for line in f]
        assert username in invocations, "generate_report.sh was not invoked with the requested username."
    finally:
        with open(report_path, "wb") as f:
            f.write(original_report)
        os.chmod(report_path, original_mode)
        with open("/app/passwd", "wb") as f:
            f.write(original_passwd)
        for path in (saved_report, probe):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
