#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import stat
import subprocess
import tempfile

SERVICES_DIR = "/home/user/services"
LOG_FILE = "/home/user/logs/api_access.log"
FIREWALL_SCRIPT = "/home/user/firewall_block.sh"
PROJECT_DIR = "/home/user/credential_manager"
CARGO_TOML = os.path.join(PROJECT_DIR, "Cargo.toml")


def expected_firewall_lines(log_path):
    malicious_ips = set()
    with open(log_path, "r") as f:
        for line in f:
            if "result: SUCCESS" in line and "KEY: EXPIRED_SYS_KEY_a8f9" in line:
                match = re.search(r"IP:\s*([\d\.]+)", line)
                if match:
                    ip = match.group(1)
                    if not ip.startswith("10.5."):
                        malicious_ips.add(ip)
    return [f"iptables -A INPUT -s {ip} -j DROP" for ip in sorted(malicious_ips)]


def test_services_credentials_rotated():
    assert os.path.isdir(SERVICES_DIR), f"{SERVICES_DIR} directory is missing"

    alpha_path = os.path.join(SERVICES_DIR, "service_alpha.json")
    beta_path = os.path.join(SERVICES_DIR, "service_beta.json")
    gamma_path = os.path.join(SERVICES_DIR, "service_gamma.json")

    assert os.path.isfile(alpha_path), f"{alpha_path} is missing"
    with open(alpha_path, "r") as f:
        alpha_data = json.load(f)
    assert alpha_data.get("api_key") == "ROTATED_SEC_KEY_b7c2", "service_alpha.json api_key was not correctly rotated"
    assert alpha_data == {
        "service_name": "alpha",
        "port": 8081,
        "api_key": "ROTATED_SEC_KEY_b7c2",
    }, "service_alpha.json fields other than api_key were altered"

    assert os.path.isfile(gamma_path), f"{gamma_path} is missing"
    with open(gamma_path, "r") as f:
        gamma_data = json.load(f)
    assert gamma_data.get("api_key") == "ROTATED_SEC_KEY_b7c2", "service_gamma.json api_key was not correctly rotated"
    assert gamma_data == {
        "service_name": "gamma",
        "port": 8083,
        "api_key": "ROTATED_SEC_KEY_b7c2",
    }, "service_gamma.json fields other than api_key were altered"

    assert os.path.isfile(beta_path), f"{beta_path} is missing"
    with open(beta_path, "r") as f:
        beta_data = json.load(f)
    assert beta_data.get("api_key") == "VALID_KEY_xyz1", "service_beta.json api_key should not have been altered"
    assert beta_data == {
        "service_name": "beta",
        "port": 8082,
        "api_key": "VALID_KEY_xyz1",
    }, "service_beta.json was otherwise altered"


def test_firewall_script_exists_and_executable():
    assert os.path.isfile(FIREWALL_SCRIPT), f"{FIREWALL_SCRIPT} was not generated"
    st = os.stat(FIREWALL_SCRIPT)
    assert bool(st.st_mode & stat.S_IXUSR), f"{FIREWALL_SCRIPT} is not executable (missing chmod +x)"


def test_firewall_script_contents():
    assert os.path.isfile(LOG_FILE), f"{LOG_FILE} is missing"
    expected_lines = expected_firewall_lines(LOG_FILE)

    assert os.path.isfile(FIREWALL_SCRIPT), f"{FIREWALL_SCRIPT} is missing"
    with open(FIREWALL_SCRIPT, "r") as f:
        script_content = f.read().strip()

    actual_lines = [line.strip() for line in script_content.splitlines() if line.strip()]
    assert actual_lines == expected_lines, (
        f"Firewall script contents do not match expected.\n"
        f"Expected:\n{chr(10).join(expected_lines)}\n"
        f"Got:\n{chr(10).join(actual_lines)}"
    )


def test_rust_project_executes_and_handles_unseen_inputs():
    assert os.path.isdir(PROJECT_DIR), f"{PROJECT_DIR} is missing"
    assert os.path.isfile(CARGO_TOML), f"{CARGO_TOML} is missing"
    assert list(Path(PROJECT_DIR).rglob("*.rs")), "credential_manager contains no Rust source files"

    token = secrets.token_hex(6)
    external_a = f"172.31.{secrets.randbelow(200) + 1}.{secrets.randbelow(200) + 1}"
    external_b = f"198.18.{secrets.randbelow(200) + 1}.{secrets.randbelow(200) + 1}"
    internal = f"10.5.{secrets.randbelow(200) + 1}.{secrets.randbelow(200) + 1}"
    failure_ip = f"203.0.113.{secrets.randbelow(200) + 1}"

    expired_name = f"rotating_{token}.json"
    valid_name = f"preserved_{token}.json"
    second_expired_name = f"extra_{token}.json"
    fixtures = {
        expired_name: {
            "service_name": f"dynamic-{token}",
            "port": 19001,
            "api_key": "EXPIRED_SYS_KEY_a8f9",
            "enabled": True,
            "metadata": {"owner": "security", "labels": ["one", "two"]},
        },
        valid_name: {
            "service_name": f"valid-{token}",
            "port": 19002,
            "api_key": f"VALID_DYNAMIC_{token}",
            "retries": 4,
            "nullable": None,
        },
        second_expired_name: {
            "service_name": f"second-{token}",
            "port": 19003,
            "api_key": "EXPIRED_SYS_KEY_a8f9",
            "description": "must remain unchanged",
        },
    }

    dynamic_log = "\n".join([
        f"[2026-01-02 03:04:01] IP: {external_b} accessed PORT: 19001 with KEY: EXPIRED_SYS_KEY_a8f9 result: SUCCESS",
        f"[2026-01-02 03:04:02] IP: {internal} accessed PORT: 19001 with KEY: EXPIRED_SYS_KEY_a8f9 result: SUCCESS",
        f"[2026-01-02 03:04:03] IP: {failure_ip} accessed PORT: 19003 with KEY: EXPIRED_SYS_KEY_a8f9 result: FAILURE",
        f"[2026-01-02 03:04:04] IP: {external_a} accessed PORT: 19002 with KEY: VALID_DYNAMIC_{token} result: SUCCESS",
        f"[2026-01-02 03:04:05] IP: {external_a} accessed PORT: 19003 with KEY: EXPIRED_SYS_KEY_a8f9 result: SUCCESS",
        f"[2026-01-02 03:04:06] IP: {external_b} accessed PORT: 19003 with KEY: EXPIRED_SYS_KEY_a8f9 result: SUCCESS",
    ]) + "\n"

    with tempfile.TemporaryDirectory() as backup_root:
        services_backup = os.path.join(backup_root, "services")
        shutil.copytree(SERVICES_DIR, services_backup)
        with open(LOG_FILE, "rb") as f:
            log_backup = f.read()
        firewall_existed = os.path.exists(FIREWALL_SCRIPT)
        firewall_backup = None
        firewall_mode = None
        if firewall_existed:
            with open(FIREWALL_SCRIPT, "rb") as f:
                firewall_backup = f.read()
            firewall_mode = stat.S_IMODE(os.stat(FIREWALL_SCRIPT).st_mode)

        try:
            shutil.rmtree(SERVICES_DIR)
            os.makedirs(SERVICES_DIR)
            for filename, data in fixtures.items():
                with open(os.path.join(SERVICES_DIR, filename), "w") as f:
                    json.dump(data, f, indent=2)
                    f.write("\n")
            with open(LOG_FILE, "w") as f:
                f.write(dynamic_log)
            if os.path.lexists(FIREWALL_SCRIPT):
                os.remove(FIREWALL_SCRIPT)

            result = subprocess.run(
                ["cargo", "run", "--quiet", "--manifest-path", CARGO_TOML],
                cwd=PROJECT_DIR,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=180,
            )
            assert result.returncode == 0, (
                f"Rust program failed with exit code {result.returncode}.\n"
                f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
            )

            for filename, original in fixtures.items():
                path = os.path.join(SERVICES_DIR, filename)
                assert os.path.isfile(path), f"Rust program removed {filename}"
                with open(path, "r") as f:
                    actual = json.load(f)
                expected = dict(original)
                if expected["api_key"] == "EXPIRED_SYS_KEY_a8f9":
                    expected["api_key"] = "ROTATED_SEC_KEY_b7c2"
                assert actual == expected, f"Incorrect or unrelated changes in {filename}: {actual!r}"

            assert os.path.isfile(FIREWALL_SCRIPT), "Rust program did not generate firewall_block.sh"
            assert os.stat(FIREWALL_SCRIPT).st_mode & stat.S_IXUSR, "Rust program did not make firewall_block.sh executable"
            expected_lines = expected_firewall_lines(LOG_FILE)
            with open(FIREWALL_SCRIPT, "r") as f:
                generated = f.read()
            assert generated.splitlines() == expected_lines, (
                f"Rust program generated incorrect firewall rules. Expected {expected_lines!r}, got {generated.splitlines()!r}"
            )
            assert generated in ("\n".join(expected_lines), "\n".join(expected_lines) + "\n"), (
                "firewall_block.sh contains extra blank or non-command content"
            )
        finally:
            if os.path.exists(SERVICES_DIR):
                shutil.rmtree(SERVICES_DIR)
            shutil.copytree(services_backup, SERVICES_DIR)
            with open(LOG_FILE, "wb") as f:
                f.write(log_backup)
            if firewall_existed:
                with open(FIREWALL_SCRIPT, "wb") as f:
                    f.write(firewall_backup)
                os.chmod(FIREWALL_SCRIPT, firewall_mode)
            elif os.path.lexists(FIREWALL_SCRIPT):
                os.remove(FIREWALL_SCRIPT)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
