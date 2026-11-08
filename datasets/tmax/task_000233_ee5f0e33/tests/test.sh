#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tarfile
import pytest

BASE = "/home/user/services"
SERVICES = ["db", "auth", "api", "web"]
EXPECTED = {
    "db": ("9001", None, "TIMEOUT=30"),
    "auth": ("9002", "http://localhost:9001", "LOG_LEVEL=debug"),
    "api": ("9003", "http://localhost:9002", None),
    "web": ("9004", "http://localhost:9003", "THEME=dark"),
}
ORIGINAL = {
    "db": b"# Database config\nLISTEN_PORT=8080\nTIMEOUT=30\n",
    "auth": b"# Auth config\nLISTEN_PORT=8081\nUPSTREAM_URL=http://localhost:8080\nLOG_LEVEL=debug\n",
    "api": b"# API config\nLISTEN_PORT=8082\nUPSTREAM_URL=http://localhost:8081\n",
    "web": b"# Web config\nLISTEN_PORT=8083\nUPSTREAM_URL=http://localhost:8082\nTHEME=dark\n",
}
EXPECTED_REPORT = [
    "db:9001:none",
    "auth:9002:http://localhost:9001",
    "api:9003:http://localhost:9002",
    "web:9004:http://localhost:9003",
]


def run_script(path):
    result = subprocess.run(["bash", path], capture_output=True, text=True)
    assert result.returncode == 0, (
        f"Script {path} failed with exit code {result.returncode}: "
        f"{result.stderr}"
    )


def read_conf(service):
    path = os.path.join(BASE, service, "service.conf")
    assert os.path.isfile(path), f"Config file {path} is missing."
    with open(path, "r") as f:
        return f.read()


def assert_correct_configs(required_markers=None):
    required_markers = required_markers or {}
    for service in SERVICES:
        content = read_conf(service)
        port, upstream, extra = EXPECTED[service]
        lines = content.splitlines()

        port_lines = [line for line in lines if re.match(r"^\s*LISTEN_PORT\s*=", line)]
        assert port_lines == [f"LISTEN_PORT={port}"], (
            f"{service}/service.conf must contain exactly one correct LISTEN_PORT assignment; "
            f"found {port_lines!r}"
        )

        upstream_lines = [line for line in lines if re.match(r"^\s*UPSTREAM_URL\s*=", line)]
        if upstream is None:
            assert upstream_lines == [], f"{service}/service.conf must not contain an upstream assignment."
        else:
            assert upstream_lines == [f"UPSTREAM_URL={upstream}"], (
                f"{service}/service.conf must contain exactly one correct UPSTREAM_URL assignment; "
                f"found {upstream_lines!r}"
            )

        if extra is not None:
            assert extra in lines, f"Original config line {extra!r} was removed from {service}/service.conf"
        if service in required_markers:
            assert required_markers[service] in lines, (
                f"Unrelated configuration line was removed from {service}/service.conf"
            )


def replace_assignment(content, key, value):
    replacement = f"{key}={value}"
    lines = content.splitlines()
    matches = [i for i, line in enumerate(lines) if re.match(rf"^\s*{re.escape(key)}\s*=", line)]
    assert len(matches) == 1
    lines[matches[0]] = replacement
    return "\n".join(lines) + "\n"


def test_complete_workflow_and_artifacts():
    backup_path = "/home/user/services_backup.tar.gz"
    assert os.path.isfile(backup_path), f"Backup file {backup_path} is missing."
    try:
        with tarfile.open(backup_path, "r:gz") as tar:
            members = tar.getmembers()
            assert any("db/service.conf" in member.name for member in members), (
                "Backup does not contain db/service.conf."
            )
            for service in SERVICES:
                suffix = f"services/{service}/service.conf"
                matches = [m for m in members if m.name.lstrip("./").endswith(suffix)]
                assert len(matches) == 1, f"Backup must contain exactly one {suffix}."
                assert matches[0].isfile(), f"Backup member {suffix} is not a regular file."
                extracted = tar.extractfile(matches[0])
                assert extracted is not None
                assert extracted.read() == ORIGINAL[service], (
                    f"Backup does not preserve the original pre-change contents of {suffix}."
                )
    except tarfile.TarError:
        pytest.fail(f"Backup file {backup_path} is not a valid gzip-compressed tarball.")

    fix_script = "/home/user/fix_network.sh"
    report_script = "/home/user/generate_report.sh"
    assert os.path.isfile(fix_script), f"Script {fix_script} is missing."
    assert os.path.isfile(report_script), f"Script {report_script} is missing."

    report_path = "/home/user/network_report.log"
    assert os.path.isfile(report_path), f"Report file {report_path} is missing."
    with open(report_path, "r") as f:
        assert f.read().strip().splitlines() == EXPECTED_REPORT, (
            "Report content does not match the expected format and order."
        )

    # Add wrong duplicate assignments and unique unrelated lines. Executing the
    # submitted fixer must repair all assignments without discarding those lines.
    markers = {}
    for service in SERVICES:
        marker = f"VERIFIER_UNRELATED_{service.upper()}={secrets.token_hex(8)}"
        markers[service] = marker
        path = os.path.join(BASE, service, "service.conf")
        with open(path, "a") as f:
            f.write(f"\n{marker}\nLISTEN_PORT={7000 + SERVICES.index(service)}\n")
            f.write(f"UPSTREAM_URL=http://wrong.invalid/{secrets.token_hex(6)}\n")

    run_script(fix_script)
    assert_correct_configs(markers)

    # A second execution must leave every configuration byte-for-byte unchanged.
    state_before = {service: read_conf(service) for service in SERVICES}
    run_script(fix_script)
    for service in SERVICES:
        assert read_conf(service) == state_before[service], (
            f"Script is not idempotent: {service}/service.conf changed on second run."
        )

    # Verify that the report script actually reads configuration data rather than
    # doing nothing or always writing the four hardcoded topology lines.
    random_base = 12000 + secrets.randbelow(20000)
    dynamic_report = []
    for index, service in enumerate(SERVICES):
        port = str(random_base + index)
        path = os.path.join(BASE, service, "service.conf")
        content = replace_assignment(read_conf(service), "LISTEN_PORT", port)
        if service == "db":
            upstream = "none"
        else:
            upstream = f"http://report-test.invalid:{random_base + index - 1}"
            content = replace_assignment(content, "UPSTREAM_URL", upstream)
        with open(path, "w") as f:
            f.write(content)
        dynamic_report.append(f"{service}:{port}:{upstream}")

    try:
        if os.path.exists(report_path):
            os.remove(report_path)
        run_script(report_script)
        assert os.path.isfile(report_path), "Report script did not create network_report.log."
        with open(report_path, "r") as f:
            assert f.read().strip().splitlines() == dynamic_report, (
                "Report script did not derive its output from the service configuration files."
            )
    finally:
        # Leave the required final state in place even after the behavioral probe.
        subprocess.run(["bash", fix_script], capture_output=True, text=True)
        subprocess.run(["bash", report_script], capture_output=True, text=True)

    assert_correct_configs(markers)
    assert os.path.isfile(report_path), "Final report is missing after executing both scripts."
    with open(report_path, "r") as f:
        assert f.read().strip().splitlines() == EXPECTED_REPORT, (
            "Final report content does not match the required topology."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
