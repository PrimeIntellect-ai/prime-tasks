#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import secrets
import shutil
import subprocess
import tempfile
from pathlib import Path
from urllib.parse import urlparse

import pytest

SCRIPT_PATH = Path("/home/user/policy_audit.sh")
RESULTS_PATH = Path("/home/user/audit_results.txt")
ACCESS_PATH = Path("/home/user/access.log")
PORTS_PATH = Path("/home/user/open_ports.txt")
DEPLOY_PATH = Path("/home/user/deploy_scripts")


def run_script():
    try:
        result = subprocess.run(
            [str(SCRIPT_PATH)], capture_output=True, text=True, timeout=10
        )
        assert result.returncode == 0, (
            f"Script failed with return code {result.returncode}. "
            f"Stderr: {result.stderr}"
        )
    except Exception as exc:
        pytest.fail(f"Failed to execute {SCRIPT_PATH}: {exc}")


def test_policy_audit_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script missing: {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script is not executable: {SCRIPT_PATH}"


def test_audit_results():
    # Preserve the original fixture and exact expected-result assertion.
    run_script()
    assert os.path.isfile(RESULTS_PATH), f"Output file missing: {RESULTS_PATH}"

    with open(RESULTS_PATH, "r") as f:
        actual_output = f.read().strip()

    expected_output = (
        "OPEN_REDIRECT_IPS: 172.16.0.4,192.168.1.100\n"
        "PRIVESC_VULN_FILES: backup.sh,stop.sh\n"
        "UNAUTHORIZED_PORTS: 22,3306,8080"
    )

    actual_lines = [line.strip() for line in actual_output.splitlines() if line.strip()]
    expected_lines = expected_output.splitlines()
    assert len(actual_lines) == len(expected_lines), (
        f"Expected {len(expected_lines)} lines in {RESULTS_PATH}, "
        f"got {len(actual_lines)}."
    )
    for expected, actual in zip(expected_lines, actual_lines):
        assert expected == actual, (
            f"Mismatch in {RESULTS_PATH}. Expected: '{expected}', Got: '{actual}'"
        )


def encode_url(value):
    return base64.b64encode(value.encode("utf-8")).decode("ascii")


def expected_report(records, files, ports):
    redirect_ips = set()
    for record in records:
        if record["endpoint"] != "login" or record["status"] != 200:
            continue
        target = record["target"]
        if not (target.startswith("http://") or target.startswith("https://")):
            continue
        hostname = urlparse(target).hostname
        if hostname not in ("localhost", "127.0.0.1"):
            redirect_ips.add(record["ip"])

    vulnerable_files = sorted(
        name for name, mode in files.items() if mode & 0o002
    )
    unauthorized_ports = sorted(
        (port for port in ports if port not in (80, 443)), key=int
    )

    return (
        "OPEN_REDIRECT_IPS: " + ",".join(sorted(redirect_ips)) + "\n"
        "PRIVESC_VULN_FILES: " + ",".join(vulnerable_files) + "\n"
        "UNAUTHORIZED_PORTS: " + ",".join(str(port) for port in unauthorized_ports)
    )


def install_scenario(records, files, ports):
    log_lines = []
    for record in records:
        payload = encode_url(record["target"])
        if record["endpoint"] == "login":
            path = f"/login?redirect={payload}"
        else:
            path = f"/other?redirect={payload}"
        log_lines.append(f"{record['ip']} GET {path} {record['status']}")

    ACCESS_PATH.write_text("\n".join(log_lines) + "\n")
    PORTS_PATH.write_text("\n".join(str(port) for port in ports) + "\n")

    if DEPLOY_PATH.exists():
        shutil.rmtree(DEPLOY_PATH)
    DEPLOY_PATH.mkdir(parents=True)
    for name, mode in files.items():
        path = DEPLOY_PATH / name
        path.write_text("#!/bin/sh\n")
        os.chmod(path, mode)

    if RESULTS_PATH.exists():
        RESULTS_PATH.unlink()


def assert_scenario(records, files, ports):
    install_scenario(records, files, ports)
    run_script()
    assert RESULTS_PATH.is_file(), f"Output file missing: {RESULTS_PATH}"
    actual = RESULTS_PATH.read_text().rstrip("\n")
    expected = expected_report(records, files, ports)
    assert actual == expected, f"Expected:\n{expected!r}\nGot:\n{actual!r}"


def test_z_policy_uses_current_inputs_and_handles_empty_results():
    token = secrets.token_hex(4)
    last_a = secrets.randbelow(80) + 10
    last_b = secrets.randbelow(80) + 110
    random_port = secrets.randbelow(40000) + 10000

    records = [
        {"ip": f"172.20.1.{last_b}", "target": f"https://outside-{token}.example/a", "status": 200, "endpoint": "login"},
        {"ip": f"10.30.2.{last_a}", "target": f"http://service-{token}.example/b", "status": 200, "endpoint": "login"},
        {"ip": "192.0.2.20", "target": "http://localhost/admin", "status": 200, "endpoint": "login"},
        {"ip": "192.0.2.21", "target": "https://127.0.0.1/private", "status": 200, "endpoint": "login"},
        {"ip": "192.0.2.22", "target": "/relative/path", "status": 200, "endpoint": "login"},
        {"ip": "192.0.2.23", "target": f"https://failed-{token}.example/", "status": 403, "endpoint": "login"},
        {"ip": "192.0.2.24", "target": f"https://other-{token}.example/", "status": 200, "endpoint": "other"},
    ]
    files = {
        f"safe_{token}.sh": 0o755,
        f"vulnerable_{token}.sh": 0o666,
        f"zz_{token}.sh": 0o777,
        f"readonly_{token}.sh": 0o644,
    }
    ports = [443, random_port, 9, 80, 2200]

    with tempfile.TemporaryDirectory() as backup_dir:
        backup = Path(backup_dir)
        shutil.copy2(ACCESS_PATH, backup / "access.log")
        shutil.copy2(PORTS_PATH, backup / "open_ports.txt")
        shutil.copytree(DEPLOY_PATH, backup / "deploy_scripts")
        had_results = RESULTS_PATH.exists()
        if had_results:
            shutil.copy2(RESULTS_PATH, backup / "audit_results.txt")

        try:
            assert_scenario(records, files, ports)

            empty_records = [
                {"ip": "198.51.100.1", "target": "/home", "status": 200, "endpoint": "login"},
                {"ip": "198.51.100.2", "target": "http://localhost/home", "status": 200, "endpoint": "login"},
                {"ip": "198.51.100.3", "target": f"https://denied-{token}.example/", "status": 500, "endpoint": "login"},
            ]
            assert_scenario(empty_records, {f"secure_{token}.sh": 0o755}, [80, 443])
        finally:
            shutil.copy2(backup / "access.log", ACCESS_PATH)
            shutil.copy2(backup / "open_ports.txt", PORTS_PATH)
            if DEPLOY_PATH.exists():
                shutil.rmtree(DEPLOY_PATH)
            shutil.copytree(backup / "deploy_scripts", DEPLOY_PATH)
            if had_results:
                shutil.copy2(backup / "audit_results.txt", RESULTS_PATH)
            elif RESULTS_PATH.exists():
                RESULTS_PATH.unlink()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
