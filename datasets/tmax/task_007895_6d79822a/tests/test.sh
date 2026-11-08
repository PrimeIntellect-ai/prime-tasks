#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import pwd
import re
import shutil
import stat
import subprocess
import textwrap
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo


def test_secure_backup_permissions():
    """Verify /home/user/secure_backup/ has exactly 750 permissions."""
    path = "/home/user/secure_backup"
    assert os.path.isdir(path), f"Directory {path} does not exist."
    mode = stat.S_IMODE(os.stat(path).st_mode)
    assert oct(mode) == '0o750', f"Permissions for {path} are {oct(mode)}, expected 0o750."


def test_archive_contents():
    """Verify archive.txt contains the correct data appended 10 times."""
    path = "/home/user/secure_backup/archive.txt"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, 'r') as f:
        content = f.read()

    expected_line = "critical system data\n"
    expected_content = expected_line * 10

    # Allow for potentially missing trailing newline or extra newlines
    assert content.strip() == expected_content.strip(), f"Content of {path} does not match expected 10 appends."
    lines = [line for line in content.split('\n') if line]
    assert len(lines) == 10, f"Expected 10 lines in {path}, found {len(lines)}."


def test_log_rotation_files():
    """Verify that backup.log and its rotated versions exist."""
    base_log = "/home/user/app_logs/backup.log"
    assert os.path.isfile(base_log), f"Log file {base_log} does not exist."

    for i in range(1, 4):
        rotated_log = f"{base_log}.{i}"
        assert os.path.isfile(rotated_log), f"Rotated log file {rotated_log} does not exist."

        # Check size limit constraint (maxBytes=60 means it should be around that or less)
        size = os.path.getsize(rotated_log)
        assert size > 0, f"Rotated log {rotated_log} is empty."
        assert size < 100, f"Rotated log {rotated_log} size {size} is too large for maxBytes=60."


def test_log_content_and_format():
    """Verify log format and content in the oldest log."""
    oldest_log = "/home/user/app_logs/backup.log.3"
    assert os.path.isfile(oldest_log), f"Oldest log {oldest_log} missing."

    with open(oldest_log, 'r') as f:
        content = f.read().strip()

    lines = content.split('\n')
    assert len(lines) > 0, "Log file is empty."

    pattern = r"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2},\d{3} - Backup successful$"
    for line in lines:
        assert re.match(pattern, line), f"Log line '{line}' does not match expected format."


def test_final_listing_artifact():
    """Verify the final_listing.txt artifact exists and contains the actual app_logs listing."""
    path = "/home/user/final_listing.txt"
    assert os.path.isfile(path), f"Artifact {path} does not exist."

    with open(path, 'r') as f:
        content = f.read()

    assert "backup.log" in content, "final_listing.txt does not contain backup.log"
    assert "backup.log.1" in content, "final_listing.txt does not contain backup.log.1"
    actual = subprocess.check_output(["ls", "-la", "/home/user/app_logs/"], text=True)
    assert content == actual, "final_listing.txt is not the output of ls -la for the current app_logs directory."


def test_required_inputs_and_script_structure():
    source_path = "/home/user/data/source.txt"
    script_path = "/home/user/backup_job.py"

    assert os.path.isdir("/home/user/data") and not os.path.islink("/home/user/data")
    assert os.path.isdir("/home/user/app_logs") and not os.path.islink("/home/user/app_logs")
    assert os.path.isdir("/home/user/secure_backup") and not os.path.islink("/home/user/secure_backup")
    assert os.path.isfile(source_path) and not os.path.islink(source_path)
    assert open(source_path, encoding="utf-8").read() == "critical system data"
    assert os.path.isfile(script_path) and not os.path.islink(script_path), f"Missing Python script {script_path}."

    source = open(script_path, encoding="utf-8").read()
    tree = ast.parse(source, filename=script_path)

    def is_environ(node):
        return isinstance(node, ast.Attribute) and node.attr == "environ"

    def is_tz_subscript(node):
        if not isinstance(node, ast.Subscript) or not is_environ(node.value):
            return False
        key = node.slice
        return isinstance(key, ast.Constant) and key.value == "TZ"

    sets_tz_via_environ = False
    calls_tzset = False
    mentions_rotating_handler = False

    for node in ast.walk(tree):
        if isinstance(node, (ast.Assign, ast.AnnAssign)):
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            if any(is_tz_subscript(target) for target in targets):
                sets_tz_via_environ = True
        if isinstance(node, ast.Call):
            func = node.func
            if isinstance(func, ast.Attribute) and func.attr == "tzset":
                calls_tzset = True
            if ((isinstance(func, ast.Name) and func.id == "RotatingFileHandler") or
                    (isinstance(func, ast.Attribute) and func.attr == "RotatingFileHandler")):
                mentions_rotating_handler = True
            if isinstance(func, ast.Attribute) and is_environ(func.value) and func.attr in {"update", "__setitem__"}:
                sets_tz_via_environ = True

    assert sets_tz_via_environ, "backup_job.py must set TZ through os.environ."
    assert calls_tzset, "backup_job.py must call time.tzset()."
    assert mentions_rotating_handler, "backup_job.py must construct a RotatingFileHandler."


def test_execute_backup_job_ten_times_from_other_working_directory():
    """Execute the submitted artifact and derive all behavioral expectations independently."""
    script_path = "/home/user/backup_job.py"
    marker = "/tmp/backup_handler_events.jsonl"
    hook_dir = "/tmp/verifier_backup_hook"
    shutil.rmtree(hook_dir, ignore_errors=True)
    os.makedirs(hook_dir, mode=0o755)

    hook = r'''
import json
import logging.handlers
import os

_original = logging.handlers.RotatingFileHandler
_marker = os.environ["VERIFIER_HANDLER_MARKER"]

class RecordingRotatingFileHandler(_original):
    def emit(self, record):
        event = {
            "filename": self.baseFilename,
            "maxBytes": self.maxBytes,
            "backupCount": self.backupCount,
            "format": getattr(self.formatter, "_fmt", None),
            "message": record.getMessage(),
            "TZ": os.environ.get("TZ"),
        }
        with open(_marker, "a", encoding="utf-8") as out:
            out.write(json.dumps(event) + "\\n")
        return super().emit(record)

logging.handlers.RotatingFileHandler = RecordingRotatingFileHandler
'''
    with open(os.path.join(hook_dir, "sitecustomize.py"), "w", encoding="utf-8") as f:
        f.write(textwrap.dedent(hook))

    if os.path.exists(marker):
        os.unlink(marker)

    # Reset only generated artifacts, then exercise the submitted script exactly ten times.
    shutil.rmtree("/home/user/app_logs")
    os.makedirs("/home/user/app_logs", mode=0o755)
    archive = "/home/user/secure_backup/archive.txt"
    if os.path.lexists(archive):
        os.unlink(archive)

    pw = pwd.getpwnam("user")
    os.chown("/home/user/data", pw.pw_uid, pw.pw_gid)
    os.chown("/home/user/data/source.txt", pw.pw_uid, pw.pw_gid)
    os.chown("/home/user/app_logs", pw.pw_uid, pw.pw_gid)
    os.chown("/home/user/secure_backup", pw.pw_uid, pw.pw_gid)
    os.chmod("/home/user/secure_backup", 0o750)

    def demote():
        os.initgroups(pw.pw_name, pw.pw_gid)
        os.setgid(pw.pw_gid)
        os.setuid(pw.pw_uid)

    env = os.environ.copy()
    env["PYTHONPATH"] = hook_dir
    env["VERIFIER_HANDLER_MARKER"] = marker
    before = datetime.now(timezone.utc)
    for _ in range(10):
        subprocess.run(
            ["python3", script_path],
            cwd="/tmp",
            env=env,
            preexec_fn=demote,
            check=True,
            timeout=15,
        )
    after = datetime.now(timezone.utc)

    expected_archive = "critical system data\n" * 10
    assert open(archive, encoding="utf-8").read() == expected_archive

    assert os.path.isfile(marker), "The script never emitted through RotatingFileHandler."
    events = [json.loads(line) for line in open(marker, encoding="utf-8") if line.strip()]
    assert len(events) == 10, f"Expected ten RotatingFileHandler emissions, got {len(events)}."
    for event in events:
        assert event["filename"] == "/home/user/app_logs/backup.log"
        assert event["maxBytes"] == 60
        assert event["backupCount"] == 3
        assert event["format"] == "%(asctime)s - %(message)s"
        assert event["message"] == "Backup successful"
        assert event["TZ"] == "Europe/Berlin"

    log_paths = ["/home/user/app_logs/backup.log"] + [f"/home/user/app_logs/backup.log.{i}" for i in range(1, 4)]
    for path in log_paths:
        assert os.path.isfile(path), f"Execution did not create {path}."
        assert 0 < os.path.getsize(path) < 60, f"Unexpected rotated log size for {path}."

    pattern = re.compile(r"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2},\d{3}) - Backup successful$")
    observed = []
    for path in log_paths:
        lines = open(path, encoding="utf-8").read().splitlines()
        assert len(lines) == 1, f"Expected one retained line in {path}, got {len(lines)}."
        match = pattern.fullmatch(lines[0])
        assert match, f"Bad runtime log line: {lines[0]!r}"
        observed.append(datetime.strptime(match.group(1), "%Y-%m-%d %H:%M:%S,%f"))

    berlin = ZoneInfo("Europe/Berlin")
    lower = before.astimezone(berlin).replace(tzinfo=None) - timedelta(seconds=2)
    upper = after.astimezone(berlin).replace(tzinfo=None) + timedelta(seconds=2)
    assert all(lower <= stamp <= upper for stamp in observed), "Log timestamps are not current Europe/Berlin local time."
    assert stat.S_IMODE(os.stat("/home/user/secure_backup").st_mode) == 0o750
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
