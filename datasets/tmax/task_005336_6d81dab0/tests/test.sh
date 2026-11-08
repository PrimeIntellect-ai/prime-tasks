#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import re
import shutil
import subprocess
import tempfile
import uuid
import pytest

SCRIPT_PATH = "/home/user/system_audit.py"
REPORT_PATH = "/home/user/audit_report.json"


def get_expected_app_data_size():
    total_size = 0
    for dirpath, _, filenames in os.walk("/home/user/app_data"):
        for f in filenames:
            fp = os.path.join(dirpath, f)
            if not os.path.islink(fp):
                total_size += os.path.getsize(fp)
    return total_size


def get_expected_default_gateway():
    with open("/home/user/mock_routes.txt", "r") as f:
        for line in f:
            if line.startswith("default via"):
                parts = line.split()
                if len(parts) >= 3:
                    return parts[2]
    return ""


def get_expected_timezone_match():
    with open("/home/user/config.json", "r") as f:
        config = json.load(f)
    expected_tz = config.get("timezone", "")

    with open("/home/user/mock_etc_timezone", "r") as f:
        actual_tz = f.read().strip()

    return expected_tz == actual_tz


def get_expected_rejected_ssh_hosts():
    rejected_hosts = []
    current_host = None

    with open("/home/user/mock_ssh_config", "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue

            host_match = re.match(r'(?i)^host\s+(.+)$', line)
            if host_match:
                current_host = host_match.group(1).strip()
                continue

            pubkey_match = re.match(r'(?i)^pubkeyauthentication\s+(no|yes)$', line)
            if pubkey_match and current_host:
                if pubkey_match.group(1).lower() == 'no':
                    rejected_hosts.append(current_host)

    return rejected_hosts


def run_script_and_load_report():
    result = subprocess.run(["python3", SCRIPT_PATH], capture_output=True, text=True)
    assert result.returncode == 0, f"Running {SCRIPT_PATH} failed with error: {result.stderr}"
    assert os.path.isfile(REPORT_PATH), f"The report {REPORT_PATH} was not generated."
    with open(REPORT_PATH, "r") as f:
        return json.load(f)


def test_system_audit_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."


def test_system_audit_script_is_executable():
    assert os.access(SCRIPT_PATH, os.X_OK), f"The script {SCRIPT_PATH} is not executable."


def test_system_audit_script_runs():
    result = subprocess.run(["python3", SCRIPT_PATH], capture_output=True, text=True)
    assert result.returncode == 0, f"Running {SCRIPT_PATH} failed with error: {result.stderr}"


def test_audit_report_exists_and_valid_json():
    assert os.path.isfile(REPORT_PATH), f"The report {REPORT_PATH} was not generated."

    with open(REPORT_PATH, "r") as f:
        try:
            json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {REPORT_PATH} does not contain valid JSON.")


def test_audit_report_contents():
    with open(REPORT_PATH, "r") as f:
        report = json.load(f)

    expected_size = get_expected_app_data_size()
    assert "app_data_size_bytes" in report, "Key 'app_data_size_bytes' missing in report."
    assert report["app_data_size_bytes"] == expected_size, f"Expected app_data_size_bytes to be {expected_size}, got {report['app_data_size_bytes']}."

    expected_gw = get_expected_default_gateway()
    assert "default_gateway" in report, "Key 'default_gateway' missing in report."
    assert report["default_gateway"] == expected_gw, f"Expected default_gateway to be '{expected_gw}', got '{report['default_gateway']}'."

    expected_tz_match = get_expected_timezone_match()
    assert "timezone_match" in report, "Key 'timezone_match' missing in report."
    assert report["timezone_match"] == expected_tz_match, f"Expected timezone_match to be {expected_tz_match}, got {report['timezone_match']}."

    expected_hosts = get_expected_rejected_ssh_hosts()
    assert "rejected_ssh_hosts" in report, "Key 'rejected_ssh_hosts' missing in report."
    assert isinstance(report["rejected_ssh_hosts"], list), "Key 'rejected_ssh_hosts' must be a list."
    assert sorted(report["rejected_ssh_hosts"]) == sorted(expected_hosts), f"Expected rejected_ssh_hosts to be {expected_hosts}, got {report['rejected_ssh_hosts']}."


def test_script_parses_changed_inputs_and_does_not_follow_symlinks():
    fixture_paths = [
        "/home/user/mock_routes.txt",
        "/home/user/config.json",
        "/home/user/mock_etc_timezone",
        "/home/user/mock_ssh_config",
    ]
    original_files = {}
    for path in fixture_paths:
        with open(path, "rb") as f:
            original_files[path] = f.read()

    app_data = "/home/user/app_data"
    backup_root = tempfile.mkdtemp(prefix="audit-fixtures-")
    backup_app_data = os.path.join(backup_root, "app_data")
    external_file = os.path.join(backup_root, "external.bin")
    shutil.move(app_data, backup_app_data)

    token = uuid.uuid4().hex[:10]
    gateway = f"192.0.2.{(int(token[:2], 16) % 200) + 1}"
    rejected_one = f"reject-{token}"
    rejected_two = f"blocked-{token}"
    accepted = f"accept-{token}"

    try:
        os.makedirs(os.path.join(app_data, "nested", "deeper"))
        with open(os.path.join(app_data, "root.bin"), "wb") as f:
            f.write(os.urandom(731))
        with open(os.path.join(app_data, "nested", "data.bin"), "wb") as f:
            f.write(os.urandom(1297))
        with open(os.path.join(app_data, "nested", "deeper", "empty.bin"), "wb"):
            pass
        with open(external_file, "wb") as f:
            f.write(os.urandom(4096))
        os.symlink(external_file, os.path.join(app_data, "ignored-file-link"))
        os.symlink(backup_app_data, os.path.join(app_data, "ignored-dir-link"))

        with open("/home/user/mock_routes.txt", "w") as f:
            f.write(
                "198.51.100.0/24 dev eth9 proto kernel scope link\n"
                f"default via {gateway} dev eth9 proto static metric 17\n"
                "203.0.113.0/24 via 198.51.100.2 dev eth9\n"
            )

        with open("/home/user/config.json", "w") as f:
            json.dump({"locale": "C.UTF-8", "timezone": f"Region/Desired-{token}"}, f)
        with open("/home/user/mock_etc_timezone", "w") as f:
            f.write(f"  Region/Actual-{token}  \n")

        with open("/home/user/mock_ssh_config", "w") as f:
            f.write(
                f"Host {accepted}\n"
                "    HostName 192.0.2.10\n"
                "    PUBKEYAUTHENTICATION yes\n\n"
                f"hOsT    {rejected_one}\n"
                "    User deploy\n"
                "    pUbKeYaUtHeNtIcAtIoN      nO\n"
                "    Port 22\n\n"
                f"HOST {rejected_two}\n"
                "    HostName 192.0.2.12\n"
                "    PubkeyAuthentication no\n"
            )

        expected_size = get_expected_app_data_size()
        expected_gateway = get_expected_default_gateway()
        expected_timezone = get_expected_timezone_match()
        expected_hosts = get_expected_rejected_ssh_hosts()

        assert expected_size == 2028
        assert expected_gateway == gateway
        assert expected_timezone is False
        assert sorted(expected_hosts) == sorted([rejected_one, rejected_two])

        if os.path.exists(REPORT_PATH):
            os.remove(REPORT_PATH)
        report = run_script_and_load_report()

        assert "app_data_size_bytes" in report
        assert report["app_data_size_bytes"] == expected_size
        assert "default_gateway" in report
        assert report["default_gateway"] == expected_gateway
        assert "timezone_match" in report
        assert report["timezone_match"] is expected_timezone
        assert "rejected_ssh_hosts" in report
        assert isinstance(report["rejected_ssh_hosts"], list)
        assert sorted(report["rejected_ssh_hosts"]) == sorted(expected_hosts)
    finally:
        if os.path.lexists(app_data):
            shutil.rmtree(app_data)
        shutil.move(backup_app_data, app_data)
        for path, contents in original_files.items():
            with open(path, "wb") as f:
                f.write(contents)
        shutil.rmtree(backup_root, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
