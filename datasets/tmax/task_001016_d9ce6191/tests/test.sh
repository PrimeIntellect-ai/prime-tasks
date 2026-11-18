#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import pytest

LOGS_DIR = "/home/user/logs"
ALERTS_DIR = "/home/user/alerts/active"
SPOOL_FILE = "/home/user/spool/mail/network_alerts.txt"
ERROR_PATTERN = re.compile(r"^\[ERROR\] Connection to (.+?) failed:")

# Preserve the original assertions for the logs supplied by the task.
EXPECTED_SYMLINKS = [
    "service_web.log",
    "service_worker.log",
    "service_auth.log",
]
UNEXPECTED_SYMLINKS = ["service_api.log"]
ORIGINAL_EXPECTED_ALERTS = {
    "ALERT: service_auth cannot reach ldap_server",
    "ALERT: service_web cannot reach db_backend",
    "ALERT: service_worker cannot reach redis_cache",
}


def derive_expected_state():
    expected_links = set()
    relationships = []
    seen_relationships = set()

    for filename in sorted(os.listdir(LOGS_DIR)):
        if not filename.endswith(".log"):
            continue

        path = os.path.join(LOGS_DIR, filename)
        if not os.path.isfile(path):
            continue

        source = filename[:-4]
        matched_this_log = False
        with open(path, "r", encoding="utf-8", errors="replace") as handle:
            for raw_line in handle:
                match = ERROR_PATTERN.match(raw_line.rstrip("\r\n"))
                if not match:
                    continue

                matched_this_log = True
                relationship = (source, match.group(1))
                if relationship not in seen_relationships:
                    seen_relationships.add(relationship)
                    relationships.append(relationship)

        if matched_this_log:
            expected_links.add(filename)

    # Python's stable sort preserves input order when one source has multiple targets.
    relationships.sort(key=lambda item: item[0])
    expected_alert_lines = [
        f"ALERT: {source} cannot reach {target}"
        for source, target in relationships
    ]
    return expected_links, expected_alert_lines


DYNAMIC_EXPECTED_LINKS, DYNAMIC_EXPECTED_ALERTS = derive_expected_state()


def test_alerts_directory_exists():
    assert os.path.exists(ALERTS_DIR), f"Directory {ALERTS_DIR} does not exist."
    assert os.path.isdir(ALERTS_DIR), f"{ALERTS_DIR} is not a directory."


@pytest.mark.parametrize("filename", EXPECTED_SYMLINKS)
def test_original_expected_symlinks(filename):
    filepath = os.path.join(ALERTS_DIR, filename)
    assert os.path.exists(filepath), f"Expected symlink {filepath} does not exist."
    assert os.path.islink(filepath), f"{filepath} is not a symbolic link."
    target = os.path.realpath(filepath)
    expected_target = os.path.join(LOGS_DIR, filename)
    assert target == expected_target, (
        f"Symlink {filepath} points to {target}, expected {expected_target}."
    )


@pytest.mark.parametrize("filename", UNEXPECTED_SYMLINKS)
def test_original_unexpected_symlinks(filename):
    filepath = os.path.join(ALERTS_DIR, filename)
    assert not os.path.exists(filepath), f"Symlink {filepath} should not exist."


def test_symlinks_match_all_log_inputs_exactly():
    actual_entries = set(os.listdir(ALERTS_DIR))
    assert actual_entries == DYNAMIC_EXPECTED_LINKS, (
        f"Alert directory entries do not match parsed logs. "
        f"Found: {sorted(actual_entries)}; expected: {sorted(DYNAMIC_EXPECTED_LINKS)}"
    )

    for filename in sorted(DYNAMIC_EXPECTED_LINKS):
        filepath = os.path.join(ALERTS_DIR, filename)
        assert os.path.islink(filepath), f"{filepath} is not a symbolic link."
        expected_target = os.path.join(LOGS_DIR, filename)
        assert os.path.realpath(filepath) == expected_target, (
            f"Symlink {filepath} does not point to {expected_target}."
        )


def test_spool_file_exists_and_permissions():
    assert os.path.exists(SPOOL_FILE), f"Spool file {SPOOL_FILE} does not exist."
    assert not os.path.islink(SPOOL_FILE), f"{SPOOL_FILE} must be a regular file, not a symlink."
    file_stat = os.lstat(SPOOL_FILE)
    assert stat.S_ISREG(file_stat.st_mode), f"{SPOOL_FILE} is not a regular file."
    permissions = stat.S_IMODE(file_stat.st_mode)
    assert permissions == 0o600, (
        f"Permissions of {SPOOL_FILE} are {oct(permissions)}, expected 0o600."
    )


def test_original_spool_assertions():
    with open(SPOOL_FILE, "r", encoding="utf-8") as handle:
        lines = [line.strip() for line in handle.readlines() if line.strip()]

    assert "To: admin@monitoring.local" in lines, (
        "Missing 'To: admin@monitoring.local' header."
    )
    assert "Subject: Network Alerts" in lines, (
        "Missing 'Subject: Network Alerts' header."
    )

    alerts = [line for line in lines if line.startswith("ALERT:")]
    assert set(alerts) == ORIGINAL_EXPECTED_ALERTS, (
        f"Alerts do not match expected. Found: {set(alerts)}; "
        f"expected: {ORIGINAL_EXPECTED_ALERTS}"
    )


def test_spool_file_exact_content_from_logs():
    expected_lines = [
        "To: admin@monitoring.local",
        "Subject: Network Alerts",
        "",
        *DYNAMIC_EXPECTED_ALERTS,
    ]
    expected_content = "\n".join(expected_lines) + "\n"

    with open(SPOOL_FILE, "r", encoding="utf-8", newline="") as handle:
        actual_content = handle.read()

    assert actual_content == expected_content, (
        "Spool file does not have the exact required headers, blank line, "
        "deduplicated alerts, ordering, or newline formatting.\n"
        f"Found: {actual_content!r}\nExpected: {expected_content!r}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
