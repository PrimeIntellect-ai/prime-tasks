#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import uuid
import random
import shutil
import subprocess
from collections import Counter
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

import pytest


def test_setup_script_exists():
    assert os.path.isfile("/home/user/setup_microservice.sh"), "/home/user/setup_microservice.sh is missing"


def test_directories_exist():
    for d in ["/home/user/mail/inbox", "/home/user/mail/processed", "/home/user/mail/archive"]:
        assert os.path.isdir(d), f"Directory {d} is missing"


def test_groups_db_content():
    db_path = "/home/user/groups.db"
    assert os.path.isfile(db_path), f"{db_path} is missing"
    with open(db_path, "r") as f:
        content = f.read().strip()
    expected = "alice:admin\nbob:staff\ncharlie:guest"
    assert content == expected, f"{db_path} content does not match expected"


def test_c_program_exists():
    assert os.path.isfile("/home/user/mail_processor.c"), "/home/user/mail_processor.c is missing"
    assert os.path.isfile("/home/user/mail_processor"), "/home/user/mail_processor executable is missing"
    assert os.access("/home/user/mail_processor", os.X_OK), "/home/user/mail_processor is not executable"


def test_files_moved_correctly():
    assert os.path.isfile("/home/user/mail/processed/msg1.eml"), "msg1.eml was not moved to processed"
    assert os.path.isfile("/home/user/mail/archive/msg2.eml"), "msg2.eml was not moved to archive"
    assert os.path.isfile("/home/user/mail/archive/msg3.eml"), "msg3.eml was not moved to archive"

    assert not os.path.isfile("/home/user/mail/inbox/msg1.eml"), "msg1.eml still in inbox"
    assert not os.path.isfile("/home/user/mail/inbox/msg2.eml"), "msg2.eml still in inbox"
    assert not os.path.isfile("/home/user/mail/inbox/msg3.eml"), "msg3.eml still in inbox"


def test_processor_log_content():
    log_path = "/home/user/mail/processor.log"
    assert os.path.isfile(log_path), f"{log_path} is missing"

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "[2023-11-15 09:30:00] Processed email from alice (Group: admin)",
        "[2023-11-15 13:45:00] Processed email from charlie (Group: guest)",
        "[2023-11-15 20:15:00] Processed email from david (Group: unknown)"
    ]

    for expected in expected_lines:
        assert expected in lines, f"Expected log entry '{expected}' not found in {log_path}"


def _run_as_user(argv, timeout=15):
    user = pwd.getpwnam("user")

    def demote():
        os.setgroups([])
        os.setgid(user.pw_gid)
        os.setuid(user.pw_uid)

    return subprocess.run(
        argv,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
        preexec_fn=demote,
        check=False,
    )


def _assert_success(result, description):
    assert result.returncode == 0, (
        f"{description} failed with status {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def _read_log_lines():
    path = "/home/user/mail/processor.log"
    if not os.path.exists(path):
        return []
    with open(path, "r") as f:
        return [line.rstrip("\n") for line in f if line.rstrip("\n")]


def _random_utc(month):
    year = random.SystemRandom().choice(range(2021, 2027))
    day = random.SystemRandom().choice(range(1, 25))
    hour = random.SystemRandom().choice(range(24))
    minute = random.SystemRandom().choice(range(60))
    second = random.SystemRandom().choice(range(60))
    return datetime(year, month, day, hour, minute, second, tzinfo=timezone.utc)


def _exercise_processor(executable, cases):
    inbox = "/home/user/mail/inbox"
    processed = "/home/user/mail/processed"
    archive = "/home/user/mail/archive"
    before = _read_log_lines()
    expected_lines = []

    for sender, group, dt in cases:
        filename = f"verify_{uuid.uuid4().hex}.eml"
        content = (
            f"Sender: {sender}\n"
            f"Date: {dt.strftime('%Y-%m-%dT%H:%M:%SZ')}\n"
            f"Subject: verifier-{uuid.uuid4().hex}\n"
        )
        source = os.path.join(inbox, filename)
        with open(source, "w") as f:
            f.write(content)

        localized = dt.astimezone(ZoneInfo("America/New_York"))
        expected_lines.append(
            f"[{localized.strftime('%Y-%m-%d %H:%M:%S')}] Processed email from {sender} (Group: {group})"
        )
        destination_dir = processed if group in ("admin", "staff") else archive
        cases._files.append((source, os.path.join(destination_dir, filename), content))

    result = _run_as_user([executable])
    _assert_success(result, f"execution of {executable}")

    after = _read_log_lines()
    assert after[:len(before)] == before, "processor.log was overwritten instead of appended to"
    added = after[len(before):]
    assert Counter(added) == Counter(expected_lines), (
        f"unexpected dynamically generated log entries: {added!r}; expected {expected_lines!r}"
    )

    for source, destination, content in cases._files:
        assert not os.path.exists(source), f"{source} was not removed from the inbox"
        assert os.path.isfile(destination), f"email was not routed to {destination}"
        with open(destination, "r") as f:
            assert f.read() == content, f"email contents changed while moving {destination}"

    stable_log = _read_log_lines()
    result = _run_as_user([executable])
    _assert_success(result, f"second execution of {executable}")
    assert _read_log_lines() == stable_log, "rerunning with an empty inbox duplicated log entries"


class CaseList(list):
    pass


def test_setup_and_processor_behavior_on_new_mail():
    expected_db = "alice:admin\nbob:staff\ncharlie:guest\n"
    setup = "/home/user/setup_microservice.sh"

    first = _run_as_user(["/bin/bash", setup])
    _assert_success(first, "first setup script execution")
    with open("/home/user/groups.db", "r") as f:
        assert f.read() == expected_db, "setup script did not produce the exact group database"

    os.chmod("/home/user/groups.db", 0o666)
    with open("/home/user/groups.db", "w") as f:
        f.write("corrupt:data\n")

    second = _run_as_user(["/bin/bash", setup])
    _assert_success(second, "setup script repair execution")
    third = _run_as_user(["/bin/bash", setup])
    _assert_success(third, "idempotent setup script execution")
    with open("/home/user/groups.db", "r") as f:
        assert f.read() == expected_db, "setup script did not recreate the exact group database"
    for directory in ["/home/user/mail/inbox", "/home/user/mail/processed", "/home/user/mail/archive"]:
        assert os.path.isdir(directory), f"setup script did not create {directory}"

    with open("/home/user/mail_processor", "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/mail_processor is not a compiled ELF executable"

    unknown_sender = "unknown_" + uuid.uuid4().hex
    binary_cases = CaseList([
        ("alice", "admin", _random_utc(1)),
        ("bob", "staff", _random_utc(7)),
        ("charlie", "guest", _random_utc(3)),
        (unknown_sender, "unknown", _random_utc(11)),
    ])
    binary_cases._files = []
    _exercise_processor("/home/user/mail_processor", binary_cases)

    rebuilt = "/tmp/mail_processor_rebuilt_" + uuid.uuid4().hex
    compile_result = subprocess.run(
        ["gcc", "/home/user/mail_processor.c", "-o", rebuilt],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
        check=False,
    )
    _assert_success(compile_result, "compilation of /home/user/mail_processor.c")
    assert os.access(rebuilt, os.X_OK), "rebuilt C program is not executable"

    source_cases = CaseList([
        ("bob", "staff", _random_utc(7)),
        ("source_" + uuid.uuid4().hex, "unknown", _random_utc(1)),
    ])
    source_cases._files = []
    _exercise_processor(rebuilt, source_cases)
    os.unlink(rebuilt)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
