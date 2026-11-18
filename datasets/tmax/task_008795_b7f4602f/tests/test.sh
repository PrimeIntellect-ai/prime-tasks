#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import secrets
import stat
import subprocess
from decimal import Decimal

import pytest


def get_expected_total():
    csv_path = "/home/user/cloud_costs.csv"
    if not os.path.exists(csv_path):
        pytest.fail(f"Required file {csv_path} is missing.")

    total = 0.0
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            cost = float(row['Cost'])
            if cost > 500.00:
                total += cost
    return f"{total:.2f}"


def email_content(total):
    return (
        "To: finops-list@local.domain\n"
        "From: billing-bot@local.domain\n"
        "Subject: Daily High Cost Alert\n"
        "\n"
        f"Total high cost: ${total}\n"
    )


def get_expected_email_content():
    return email_content(get_expected_total())


def test_directories_exist():
    archive_dir = "/home/user/reports/archive/"
    outbox_dir = "/home/user/mail_spool/outbox/"

    assert os.path.isdir(archive_dir), f"Directory {archive_dir} does not exist."
    assert os.path.isdir(outbox_dir), f"Directory {outbox_dir} does not exist."


def test_symlink_exists_and_correct():
    symlink_path = "/home/user/reports/latest_alert.eml"
    target_path = "/home/user/reports/archive/cost_alert.eml"

    assert os.path.islink(symlink_path), f"{symlink_path} is not a symbolic link."

    actual_target = os.readlink(symlink_path)
    assert actual_target == target_path, f"Symlink points to {actual_target} instead of {target_path}."


def test_archive_email_content():
    email_path = "/home/user/reports/archive/cost_alert.eml"
    assert os.path.isfile(email_path), f"File {email_path} does not exist."

    with open(email_path, 'r', encoding='utf-8') as f:
        content = f.read()

    expected_content = get_expected_email_content()
    assert content.strip() == expected_content.strip(), f"Content of {email_path} does not match expected format and calculation."


def test_outbox_email_content():
    email_path = "/home/user/mail_spool/outbox/cost_alert.eml"
    assert os.path.isfile(email_path), f"File {email_path} does not exist."

    with open(email_path, 'r', encoding='utf-8') as f:
        content = f.read()

    expected_content = get_expected_email_content()
    assert content.strip() == expected_content.strip(), f"Content of {email_path} does not match expected format and calculation."


def test_script_executes_and_processes_csv():
    script_path = "/home/user/process_costs.py"
    csv_path = "/home/user/cloud_costs.csv"
    archive_path = "/home/user/reports/archive/cost_alert.eml"
    outbox_path = "/home/user/mail_spool/outbox/cost_alert.eml"

    assert os.path.lexists(script_path), f"Required script {script_path} is missing."
    mode = os.lstat(script_path).st_mode
    assert stat.S_ISREG(mode), f"{script_path} must be a regular Python script."

    with open(csv_path, "rb") as f:
        original_csv = f.read()

    high1 = Decimal(secrets.randbelow(40000) + 50100) / Decimal(100)
    high2 = Decimal(secrets.randbelow(60000) + 70000) / Decimal(100)
    low = Decimal(secrets.randbelow(49999)) / Decimal(100)
    challenge_csv = (
        "ResourceID,Service,Cost\n"
        f"challenge-high-a,Compute,{high1:.2f}\n"
        f"challenge-low,Storage,{low:.2f}\n"
        "challenge-boundary,Network,500.00\n"
        f"challenge-high-b,Database,{high2:.2f}\n"
    )
    challenge_expected = email_content(f"{high1 + high2:.2f}")

    try:
        with open(csv_path, "w", encoding="utf-8", newline="") as f:
            f.write(challenge_csv)
        if os.path.lexists(archive_path):
            os.unlink(archive_path)

        result = subprocess.run(
            ["python3", script_path],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        assert result.returncode == 0, f"Executing {script_path} failed: {result.stderr}"
        assert os.path.isfile(archive_path), f"{script_path} did not generate {archive_path}."
        with open(archive_path, "r", encoding="utf-8") as f:
            actual = f.read()
        assert actual.strip() == challenge_expected.strip(), "The script did not recompute the report from the supplied CSV data."
    finally:
        with open(csv_path, "wb") as f:
            f.write(original_csv)
        if os.path.lexists(archive_path):
            os.unlink(archive_path)
        restore = subprocess.run(
            ["python3", script_path],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        assert restore.returncode == 0, f"Executing {script_path} on the original CSV failed: {restore.stderr}"

    expected = get_expected_email_content()
    with open(archive_path, "r", encoding="utf-8") as f:
        assert f.read().strip() == expected.strip(), "Archive report was not restored from the original CSV."
    with open(outbox_path, "r", encoding="utf-8") as f:
        assert f.read().strip() == expected.strip(), "Outbox report does not match the original CSV after script execution."


def test_standard_user_can_read_results():
    readable_files = [
        "/home/user/process_costs.py",
        "/home/user/reports/archive/cost_alert.eml",
        "/home/user/reports/latest_alert.eml",
        "/home/user/mail_spool/outbox/cost_alert.eml",
    ]
    traversable_dirs = [
        "/home/user/reports",
        "/home/user/reports/archive",
        "/home/user/mail_spool",
        "/home/user/mail_spool/outbox",
    ]

    for path in readable_files:
        result = subprocess.run(["runuser", "-u", "user", "--", "test", "-r", path])
        assert result.returncode == 0, f"{path} is not readable by the standard user."

    for path in traversable_dirs:
        result = subprocess.run(["runuser", "-u", "user", "--", "test", "-r", path, "-a", "-x", path])
        assert result.returncode == 0, f"{path} is not readable and traversable by the standard user."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
