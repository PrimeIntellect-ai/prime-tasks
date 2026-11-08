#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import io
import json
import os
import random
import re
import shutil
import subprocess
import tarfile
import uuid
from zoneinfo import ZoneInfo

import pytest

SCRIPT_PATH = "/home/user/restore_tester.sh"
BACKUP_PATH = "/home/user/backup.tar.gz"
RESTORE_DIR = "/home/user/restore_test"
REPORT_PATH = "/home/user/restore_report.json"


def clean_outputs():
    shutil.rmtree(RESTORE_DIR, ignore_errors=True)
    try:
        os.remove(REPORT_PATH)
    except FileNotFoundError:
        pass


def run_restore_script():
    result = subprocess.run([SCRIPT_PATH], capture_output=True, text=True)
    assert result.returncode == 0, (
        f"Script failed with return code {result.returncode}.\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )


def archive_member_bytes(name):
    with tarfile.open(BACKUP_PATH, "r:gz") as archive:
        member = archive.getmember(name)
        extracted = archive.extractfile(member)
        assert extracted is not None, f"Archive member {name} is not a regular file."
        return extracted.read()


@pytest.fixture(scope="session", autouse=True)
def run_script():
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} is not a regular file."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."

    clean_outputs()
    run_restore_script()


def test_extracted_files():
    assert os.path.isdir(RESTORE_DIR), "/home/user/restore_test/ directory does not exist."

    for name in ("deploy_pipeline.log", "proxy_template.conf"):
        output_path = os.path.join(RESTORE_DIR, name)
        assert os.path.exists(output_path), f"{name} was not extracted to /home/user/restore_test/."
        assert os.path.isfile(output_path), f"{output_path} is not a regular file."
        with open(output_path, "rb") as output_file:
            assert output_file.read() == archive_member_bytes(name), (
                f"{output_path} does not match the corresponding file in backup.tar.gz."
            )


def test_local_proxy_conf():
    conf_path = "/home/user/restore_test/local_proxy.conf"
    assert os.path.exists(conf_path), f"{conf_path} does not exist."

    with open(conf_path, "r") as f:
        content = f.read()

    assert "listen 8080;" in content, "listen 8080; not found in local_proxy.conf"
    assert "listen 8443;" in content, "listen 8443; not found in local_proxy.conf"
    assert "listen 80;" not in content, "listen 80; should have been replaced."
    assert "listen 443;" not in content, "listen 443; should have been replaced."

    template = archive_member_bytes("proxy_template.conf")
    expected = template.replace(b"listen 80;", b"listen 8080;").replace(
        b"listen 443;", b"listen 8443;"
    )
    with open(conf_path, "rb") as f:
        assert f.read() == expected, (
            "local_proxy.conf is not the extracted proxy template with the required port replacements."
        )


def test_restore_report_json():
    report_path = "/home/user/restore_report.json"
    assert os.path.exists(report_path), f"{report_path} does not exist."

    with open(report_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{report_path} is not valid JSON.")

    assert "last_successful_deploy_tokyo" in data, "Missing key 'last_successful_deploy_tokyo' in JSON."
    assert data["last_successful_deploy_tokyo"] == "2023-10-05 01:30:00", f"Incorrect timestamp: {data['last_successful_deploy_tokyo']}"

    assert "proxy_listen_ports" in data, "Missing key 'proxy_listen_ports' in JSON."
    assert isinstance(data["proxy_listen_ports"], list), "'proxy_listen_ports' must be a JSON array."

    ports = set(str(p) for p in data["proxy_listen_ports"])
    assert ports == {"8080", "8443"}, f"Incorrect ports in JSON: {data['proxy_listen_ports']}"
    assert set(data) == {"last_successful_deploy_tokyo", "proxy_listen_ports"}, (
        f"Unexpected JSON keys: {set(data)}"
    )
    assert data["proxy_listen_ports"] == ["8080", "8443"], (
        "proxy_listen_ports must contain the modified ports in configuration order."
    )


def test_script_derives_results_from_backup():
    original_archive = open(BACKUP_PATH, "rb").read()
    token = uuid.uuid4().hex
    base = datetime.datetime.fromtimestamp(
        random.SystemRandom().randint(1577836800, 1893456000),
        tz=datetime.timezone.utc,
    ).replace(microsecond=0)
    old_success = base
    latest_success = base + datetime.timedelta(hours=5, minutes=17)
    later_failure = base + datetime.timedelta(hours=9)

    def stamp(value):
        return value.strftime("%Y-%m-%d %H:%M:%S")

    # The newest successful deployment is deliberately not the last successful
    # line, so the script must compare timestamps rather than trust line order.
    dynamic_log = (
        f"[{stamp(latest_success)} UTC] DEPLOY_ID: 902 STATUS: SUCCESS\n"
        f"[{stamp(later_failure)} UTC] DEPLOY_ID: 903 STATUS: FAILED\n"
        f"[{stamp(old_success)} UTC] DEPLOY_ID: 901 STATUS: SUCCESS\n"
    ).encode()
    dynamic_template = (
        "server {\n"
        "    listen 80;\n"
        f"    server_name {token}.example.test;\n"
        "}\n"
        "server {\n"
        "    listen 443;\n"
        f"    # randomized marker: {token}\n"
        "}\n"
    ).encode()

    try:
        with tarfile.open(BACKUP_PATH, "w:gz") as archive:
            for name, content in (
                ("deploy_pipeline.log", dynamic_log),
                ("proxy_template.conf", dynamic_template),
            ):
                info = tarfile.TarInfo(name)
                info.size = len(content)
                info.mode = 0o644
                archive.addfile(info, io.BytesIO(content))

        clean_outputs()
        run_restore_script()

        for name, expected in (
            ("deploy_pipeline.log", dynamic_log),
            ("proxy_template.conf", dynamic_template),
        ):
            with open(os.path.join(RESTORE_DIR, name), "rb") as f:
                assert f.read() == expected, f"The script did not extract the current {name}."

        expected_conf = dynamic_template.replace(
            b"listen 80;", b"listen 8080;"
        ).replace(b"listen 443;", b"listen 8443;")
        with open(os.path.join(RESTORE_DIR, "local_proxy.conf"), "rb") as f:
            assert f.read() == expected_conf, (
                "local_proxy.conf was not derived from the current proxy_template.conf."
            )

        with open(REPORT_PATH, "r") as f:
            report = json.load(f)

        expected_tokyo = latest_success.astimezone(ZoneInfo("Asia/Tokyo")).strftime(
            "%Y-%m-%d %H:%M:%S"
        )
        assert set(report) == {"last_successful_deploy_tokyo", "proxy_listen_ports"}
        assert report["last_successful_deploy_tokyo"] == expected_tokyo, (
            "The reported timestamp was not derived from the latest successful deployment."
        )
        ports = re.findall(rb"\blisten\s+(\d+)\s*;", expected_conf)
        assert report["proxy_listen_ports"] == [p.decode() for p in ports], (
            "The reported ports were not extracted from local_proxy.conf."
        )
    finally:
        with open(BACKUP_PATH, "wb") as f:
            f.write(original_archive)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
