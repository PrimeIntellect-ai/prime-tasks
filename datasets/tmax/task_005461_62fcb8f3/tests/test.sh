#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import os
import re
import secrets
import subprocess
import tarfile
import uuid
from datetime import datetime
from zoneinfo import ZoneInfo


def test_script_exists_and_executable():
    script_path = "/home/user/restore_test.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_restored_data():
    data_path = "/home/user/restored_data/data.txt"
    assert os.path.isfile(data_path), f"Restored data file {data_path} does not exist."
    with open(data_path, "r") as f:
        content = f.read().strip()
    assert content == "Database dump successful", f"Unexpected content in {data_path}: {content}"


def test_restore_report():
    report_path = "/home/user/restore_report.txt"
    assert os.path.isfile(report_path), f"Report file {report_path} does not exist."

    with open(report_path, "r") as f:
        content = f.read().strip().split('\n')

    expected_lines = [
        "[2023-07-01 09:00:00] Primary db synced",
        "[2023-07-02 09:00:00] Secondary db synced"
    ]

    for expected in expected_lines:
        assert expected in content, f"Expected line '{expected}' not found in {report_path}."


def test_crontab_scheduled():
    try:
        result = subprocess.run(["crontab", "-l"], capture_output=True, text=True, check=True)
        crontab_output = result.stdout
    except subprocess.CalledProcessError:
        assert False, "Failed to read crontab or no crontab exists."

    match = re.search(r'^0\s+3\s+\*\s+\*\s+\*\s+.*?/home/user/restore_test\.sh', crontab_output, re.MULTILINE)
    assert match is not None, "Crontab does not contain the correct schedule for /home/user/restore_test.sh at 3:00 AM."

    exact_line = "0 3 * * * /home/user/restore_test.sh"
    assert exact_line in crontab_output.splitlines(), "Crontab does not contain the exact required schedule line."


def test_cron_backup_file():
    path = "/home/user/cron_backup.txt"
    assert os.path.isfile(path), f"Cron backup file {path} does not exist."
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "0 3 * * * /home/user/restore_test.sh", \
        f"Unexpected cron schedule in {path}: {content!r}"


def test_script_idempotency():
    script_path = "/home/user/restore_test.sh"
    report_path = "/home/user/restore_report.txt"

    with open(report_path, "r") as f:
        before_content = f.read()

    result = subprocess.run([script_path], capture_output=True, text=True)
    assert result.returncode == 0, f"Script failed on subsequent run (not idempotent). Error: {result.stderr}"

    with open(report_path, "r") as f:
        after_content = f.read()

    assert before_content == after_content, "Report file content changed on subsequent run, script is not idempotent."


def _write_archive(path, members):
    with tarfile.open(path, "w:gz") as archive:
        for name, content in members.items():
            payload = content.encode("utf-8")
            info = tarfile.TarInfo(name=name)
            info.size = len(payload)
            info.mode = 0o644
            archive.addfile(info, io.BytesIO(payload))
    os.chmod(path, 0o644)


def _run_as_user(script):
    result = subprocess.run(
        ["runuser", "-u", "user", "--", script],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"Restore script failed as user: {result.stderr}"


def test_dynamic_extraction_conversion_and_conditional_skip():
    script = "/home/user/restore_test.sh"
    archive = "/home/user/backup.tar.gz"
    restored = "/home/user/restored_data"
    report = "/home/user/restore_report.txt"

    subprocess.run(["rm", "-rf", restored], check=True)
    if os.path.exists(report):
        os.remove(report)

    token = uuid.uuid4().hex
    data_content = f"dynamic-data-{token}\n"
    epoch1 = 1500000000 + secrets.randbelow(300000000)
    epoch2 = epoch1 + 86400 + secrets.randbelow(3600)
    message1 = f"dynamic primary {token}"
    message2 = f"dynamic secondary {token[::-1]}"
    log_content = f"{epoch1} {message1}\n{epoch2} {message2}\n"

    _write_archive(archive, {
        "data.txt": data_content,
        "backup.log": log_content,
    })
    _run_as_user(script)

    data_path = os.path.join(restored, "data.txt")
    log_path = os.path.join(restored, "backup.log")
    assert os.path.isfile(data_path), "Script did not extract data.txt when it was absent."
    assert os.path.isfile(log_path), "Script did not extract backup.log directly into restored_data."

    with open(data_path, "r") as f:
        assert f.read() == data_content, "Extracted data.txt does not match the test archive."
    with open(log_path, "r") as f:
        assert f.read() == log_content, "Extracted backup.log does not match the test archive."

    tokyo = ZoneInfo("Asia/Tokyo")
    expected_report = (
        f"[{datetime.fromtimestamp(epoch1, tokyo).strftime('%Y-%m-%d %H:%M:%S')}] {message1}\n"
        f"[{datetime.fromtimestamp(epoch2, tokyo).strftime('%Y-%m-%d %H:%M:%S')}] {message2}\n"
    )
    with open(report, "r") as f:
        assert f.read() == expected_report, "Report was not derived correctly from the extracted log."

    changed_token = uuid.uuid4().hex
    _write_archive(archive, {
        "data.txt": f"replacement-{changed_token}\n",
        "backup.log": f"0 replacement message {changed_token}\n",
        "must_not_extract.txt": "conditional extraction failed\n",
    })

    before_data = open(data_path, "rb").read()
    before_log = open(log_path, "rb").read()
    _run_as_user(script)

    assert open(data_path, "rb").read() == before_data, "data.txt was overwritten even though it already existed."
    assert open(log_path, "rb").read() == before_log, "backup.log was overwritten even though data.txt already existed."
    assert not os.path.exists(os.path.join(restored, "must_not_extract.txt")), \
        "Archive contents were extracted even though data.txt already existed."
    with open(report, "r") as f:
        assert f.read() == expected_report, "Rerunning the script did not regenerate the same report from the unchanged log."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
