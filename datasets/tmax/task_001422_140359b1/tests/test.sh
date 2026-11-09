#!/bin/bash
mkdir -p /logs/verifier

cat > /tmp/task_verifier.py <<'PY'
import base64
import datetime
import email
from email import policy
import glob
import json
import os
import re
import secrets
import socket
import subprocess
import sys
import tarfile
import time

APP_LOG = "/home/user/legacy_logs/app.log"
PARSE_SCRIPT = "/home/user/migration/parse_logs.sh"
SUMMARY = "/home/user/migration/critical_summary.txt"
MIGRATOR = "/home/user/migration/migrator.py"
BACKUP_DIR = "/home/user/backups"
CAPTURE = "/tmp/verifier_smtp_capture.jsonl"
READY = "/tmp/verifier_smtp_ready"

EXPECTED_LINES = [
    "2023-10-12 14:21:12 | Database connection timeout",
    "2023-10-12 14:22:11 | Cache server unreachable",
    "2023-10-12 14:23:00 | Network partition detected",
    "2023-10-12 14:25:01 | File system read-only",
    "2023-10-12 14:26:00 | Process crashed unexpectedly",
    "2023-10-12 14:27:00 | Disk space 99% full",
]
EXPECTED_SUMMARY = "\n".join(EXPECTED_LINES) + "\n"


def run(cmd, timeout=30):
    return subprocess.run(cmd, check=True, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, timeout=timeout)


def read_summary_lines():
    assert os.path.isfile(SUMMARY), f"File {SUMMARY} does not exist."
    with open(SUMMARY, "r") as f:
        return f.read().strip().splitlines()


def assert_original_summary():
    content = read_summary_lines()
    assert len(content) == len(EXPECTED_LINES), (
        f"Expected {len(EXPECTED_LINES)} lines in {SUMMARY}, but found {len(content)}."
    )
    for expected, actual in zip(EXPECTED_LINES, content):
        assert expected == actual, (
            f"Line mismatch in {SUMMARY}. Expected: '{expected}', Got: '{actual}'"
        )


def test_parser():
    assert os.path.isfile(PARSE_SCRIPT), f"{PARSE_SCRIPT} does not exist."
    assert os.access(PARSE_SCRIPT, os.X_OK), f"{PARSE_SCRIPT} is not executable."
    with open(PARSE_SCRIPT, "rb") as f:
        first_line = f.readline().decode("utf-8", "replace").lower()
    assert first_line.startswith("#!") and ("sh" in first_line or "bash" in first_line), \
        f"{PARSE_SCRIPT} is not an executable shell script."

    original_log = open(APP_LOG, "rb").read()
    try:
        run([PARSE_SCRIPT])
        assert_original_summary()

        token = secrets.token_hex(12)
        dynamic_log = (
            f"ignore {token}\n"
            f"2042-01-02 03:04:05 [CRITICAL] dynamic first {token}\n"
            f"2042-01-02 03:04:06 [WARN] not critical {token}\n"
            f"2042-01-02 03:04:07 [CRITICAL] dynamic second {token}\n"
        )
        with open(APP_LOG, "w") as f:
            f.write(dynamic_log)
        run([PARSE_SCRIPT])
        expected_dynamic = [
            f"2042-01-02 03:04:05 | dynamic first {token}",
            f"2042-01-02 03:04:07 | dynamic second {token}",
        ]
        assert read_summary_lines() == expected_dynamic, \
            "parse_logs.sh did not derive the required output from the current log input."
    finally:
        with open(APP_LOG, "wb") as f:
            f.write(original_log)

    run([PARSE_SCRIPT])
    assert_original_summary()


def start_smtp():
    server_source = r'''
import base64
import json
import time
from aiosmtpd.controller import Controller

CAPTURE = "/tmp/verifier_smtp_capture.jsonl"
READY = "/tmp/verifier_smtp_ready"

class Handler:
    async def handle_DATA(self, server, session, envelope):
        record = {
            "mail_from": envelope.mail_from,
            "rcpt_tos": envelope.rcpt_tos,
            "content": base64.b64encode(envelope.content).decode("ascii"),
        }
        with open(CAPTURE, "a") as f:
            f.write(json.dumps(record) + "\\n")
        return "250 Message accepted for delivery"

controller = Controller(Handler(), hostname="127.0.0.1", port=8025)
controller.start()
with open(READY, "w") as f:
    f.write("ready")
try:
    while True:
        time.sleep(1)
finally:
    controller.stop()
'''
    with open("/tmp/verifier_smtp.py", "w") as f:
        f.write(server_source)
    for path in (CAPTURE, READY):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass
    proc = subprocess.Popen([sys.executable, "/tmp/verifier_smtp.py"],
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    deadline = time.time() + 8
    while time.time() < deadline:
        if proc.poll() is not None:
            out, err = proc.communicate()
            raise AssertionError(f"Verifier SMTP server failed to start: {out} {err}")
        if os.path.exists(READY):
            return proc
        time.sleep(0.05)
    proc.terminate()
    raise AssertionError("Verifier SMTP server did not become ready.")


def captured_messages():
    if not os.path.exists(CAPTURE):
        return []
    with open(CAPTURE) as f:
        return [json.loads(line) for line in f if line.strip()]


def clear_capture():
    try:
        os.unlink(CAPTURE)
    except FileNotFoundError:
        pass


def prepare_backups():
    os.makedirs(BACKUP_DIR, exist_ok=True)
    for path in glob.glob(os.path.join(BACKUP_DIR, "*.tar.gz")):
        os.unlink(path)
    fixtures = [
        ("backup_20231001_000000.tar.gz", 1696118400),
        ("backup_20231002_000000.tar.gz", 1696204800),
        ("backup_20231003_000000.tar.gz", 1696291200),
    ]
    for name, stamp in fixtures:
        path = os.path.join(BACKUP_DIR, name)
        open(path, "wb").close()
        os.utime(path, (stamp, stamp))


def run_migrator():
    return run([sys.executable, MIGRATOR], timeout=30)


def identify_new_archive(before, started, finished):
    after = set(glob.glob(os.path.join(BACKUP_DIR, "*.tar.gz")))
    candidates = after - before
    assert candidates, "migrator.py did not create a new backup archive."
    matching = []
    for path in candidates:
        match = re.fullmatch(r"backup_(\d{8}_\d{6})\.tar\.gz", os.path.basename(path))
        if not match:
            continue
        named_time = datetime.datetime.strptime(match.group(1), "%Y%m%d_%H%M%S").timestamp()
        if started - 2 <= named_time <= finished + 2:
            matching.append(path)
    assert matching, "No newly created archive used a current backup_YYYYMMDD_HHMMSS.tar.gz timestamp."
    return max(matching, key=os.path.getmtime)


def validate_archive(path):
    assert tarfile.is_tarfile(path), f"New backup {path} is not a valid tar archive."
    with tarfile.open(path, "r:gz") as archive:
        members = {m.name.lstrip("./"): m for m in archive.getmembers()}

        def find_member(filename):
            matches = [m for name, m in members.items()
                       if name == f"app_data/{filename}" or name.endswith(f"/app_data/{filename}")]
            assert matches, f"New backup does not contain app_data/{filename}."
            return matches[0]

        config = archive.extractfile(find_member("config.json"))
        users = archive.extractfile(find_member("users.db"))
        assert config is not None and config.read() == b"dummy data 1\n", \
            "Backed-up config.json has incorrect contents."
        assert users is not None and users.read() == b"dummy data 2\n", \
            "Backed-up users.db has incorrect contents."


def test_migrator_and_email():
    assert os.path.isfile(MIGRATOR), f"{MIGRATOR} does not exist."
    prepare_backups()

    # Exactly five lines must not trigger an alert, while backup creation still runs.
    with open(SUMMARY, "w") as f:
        f.write("\n".join(EXPECTED_LINES[:5]) + "\n")
    clear_capture()
    before = set(glob.glob(os.path.join(BACKUP_DIR, "*.tar.gz")))
    started = time.time()
    run_migrator()
    finished = time.time()
    first_archive = identify_new_archive(before, started, finished)
    validate_archive(first_archive)
    time.sleep(0.4)
    assert captured_messages() == [], "An email was sent when the summary had only five lines."

    # Six lines must produce another current backup and a real SMTP transaction.
    with open(SUMMARY, "w") as f:
        f.write(EXPECTED_SUMMARY)
    time.sleep(1.1)  # The required filename has one-second resolution.
    clear_capture()
    before = set(glob.glob(os.path.join(BACKUP_DIR, "*.tar.gz")))
    started = time.time()
    run_migrator()
    finished = time.time()
    newest_archive = identify_new_archive(before, started, finished)
    validate_archive(newest_archive)

    deadline = time.time() + 3
    messages = []
    while time.time() < deadline:
        messages = captured_messages()
        if messages:
            break
        time.sleep(0.05)
    assert len(messages) == 1, f"Expected exactly one SMTP alert, captured {len(messages)}."

    record = messages[0]
    raw = base64.b64decode(record["content"])
    raw_text = raw.decode("utf-8", "replace")
    assert "Subject: Migration Alert: Critical Errors Detected" in raw_text, \
        "Email subject not found in sent email."
    assert "migrator@cloudops.local" in raw_text, "Sender email not found in sent email."
    assert "admin@cloudops.local" in raw_text, "Recipient email not found in sent email."
    assert "Database connection timeout" in raw_text, \
        "Email body does not contain the critical summary contents."

    assert record["mail_from"] == "migrator@cloudops.local", "Incorrect SMTP envelope sender."
    assert record["rcpt_tos"] == ["admin@cloudops.local"], "Incorrect SMTP envelope recipient."
    message = email.message_from_bytes(raw, policy=policy.default)
    assert message.get("Subject") == "Migration Alert: Critical Errors Detected", "Incorrect email subject."
    assert message.get("From") == "migrator@cloudops.local", "Incorrect From header."
    assert message.get("To") == "admin@cloudops.local", "Incorrect To header."
    body_part = message.get_body(preferencelist=("plain",)) if message.is_multipart() else message
    body = body_part.get_content()
    assert body == EXPECTED_SUMMARY, "Email body is not the exact contents of critical_summary.txt."

    tar_files = glob.glob(os.path.join(BACKUP_DIR, "*.tar.gz"))
    assert len(tar_files) == 3, \
        f"Expected exactly 3 .tar.gz files in {BACKUP_DIR}/, but found {len(tar_files)}: {tar_files}"
    oldest = os.path.join(BACKUP_DIR, "backup_20231001_000000.tar.gz")
    second_oldest = os.path.join(BACKUP_DIR, "backup_20231002_000000.tar.gz")
    third_oldest = os.path.join(BACKUP_DIR, "backup_20231003_000000.tar.gz")
    assert not os.path.exists(oldest), f"Oldest backup {oldest} should have been deleted by rotation."
    assert not os.path.exists(second_oldest), "Rotation did not continue deleting backups by modification time."
    assert os.path.exists(third_oldest), "Rotation deleted a newer backup instead of the oldest backups."
    assert_original_summary()


def main():
    test_parser()
    smtp = start_smtp()
    try:
        test_migrator_and_email()
    finally:
        smtp.terminate()
        try:
            smtp.wait(timeout=3)
        except subprocess.TimeoutExpired:
            smtp.kill()


if __name__ == "__main__":
    main()
PY

if python3 /tmp/task_verifier.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
