#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import re
import stat
import subprocess
import sys

import pytest


def test_audit_report():
    report_path = "/home/user/audit_report.json"
    assert os.path.isfile(report_path), f"Audit report missing at {report_path}"

    with open(report_path, "r") as f:
        try:
            report_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Audit report at {report_path} is not valid JSON")

    expected_cwes = [78, 798]
    assert "vulnerable_script_cwes" in report_data, "Missing 'vulnerable_script_cwes' in audit report"
    assert report_data["vulnerable_script_cwes"] == expected_cwes, f"Expected CWEs {expected_cwes}, got {report_data['vulnerable_script_cwes']}"

    expected_ip = "198.51.100.55"
    assert "suspicious_ip" in report_data, "Missing 'suspicious_ip' in audit report"
    assert report_data["suspicious_ip"] == expected_ip, f"Expected IP {expected_ip}, got {report_data['suspicious_ip']}"

    expected_suid = "/home/user/bin/backup_creds"
    assert "suid_binary" in report_data, "Missing 'suid_binary' in audit report"
    assert report_data["suid_binary"] == expected_suid, f"Expected SUID binary {expected_suid}, got {report_data['suid_binary']}"

    # Derive the CWE findings from the supplied vulnerable script.
    vulnerable_path = "/home/user/app/cred_manager.py"
    with open(vulnerable_path, "r") as f:
        vulnerable_tree = ast.parse(f.read(), filename=vulnerable_path)

    has_hardcoded_credential = any(
        isinstance(node, (ast.Assign, ast.AnnAssign))
        and isinstance(getattr(node, "value", None), ast.Constant)
        and isinstance(node.value.value, str)
        and bool(node.value.value)
        and any(
            marker in name.upper()
            for name in (
                [target.id for target in node.targets if isinstance(target, ast.Name)]
                if isinstance(node, ast.Assign)
                else ([node.target.id] if isinstance(node.target, ast.Name) else [])
            )
            for marker in ("PASS", "PASSWORD", "CREDENTIAL", "SECRET")
        )
        for node in ast.walk(vulnerable_tree)
    )
    has_os_command_execution = any(
        isinstance(node, ast.Call)
        and isinstance(node.func, ast.Attribute)
        and isinstance(node.func.value, ast.Name)
        and node.func.value.id == "os"
        and node.func.attr in ("system", "popen")
        for node in ast.walk(vulnerable_tree)
    )
    derived_cwes = sorted(
        ([798] if has_hardcoded_credential else [])
        + ([78] if has_os_command_execution else [])
    )
    assert derived_cwes == expected_cwes, f"Vulnerable script did not contain the expected flaws: {derived_cwes}"
    assert report_data["vulnerable_script_cwes"] == derived_cwes

    # Parse the supplied access log rather than trusting a verifier constant alone.
    suspicious_ips = []
    with open("/home/user/logs/access.log", "r") as f:
        for line in f:
            match = re.match(r'^(\S+).*"\S+\s+(\S+)\s+HTTP/[^\"]+"\s+(\d{3})\b', line)
            if match:
                ip, target, status = match.groups()
                if target.split("?", 1)[0] == "/app/secrets" and status == "200":
                    suspicious_ips.append(ip)
    assert len(suspicious_ips) == 1, f"Expected one successful secrets access, got {suspicious_ips}"
    assert report_data["suspicious_ip"] == suspicious_ips[0]

    # Search the requested directory for the actual SUID file.
    suid_paths = []
    for root, _, files in os.walk("/home/user/bin"):
        for filename in files:
            path = os.path.abspath(os.path.join(root, filename))
            mode = os.stat(path).st_mode
            if stat.S_ISREG(mode) and mode & stat.S_ISUID:
                suid_paths.append(path)
    assert expected_suid in suid_paths, f"Expected SUID binary not present; found {suid_paths}"
    assert report_data["suid_binary"] in suid_paths


def test_new_secrets_json():
    secrets_path = "/home/user/app/new_secrets.json"
    assert os.path.isfile(secrets_path), f"New secrets file missing at {secrets_path}"

    with open(secrets_path, "r") as f:
        try:
            secrets_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Secrets file at {secrets_path} is not valid JSON")

    assert "db_password" in secrets_data, "Missing 'db_password' key in new secrets file"
    password = secrets_data["db_password"]

    assert isinstance(password, str), "Password is not a string"
    assert len(password) == 16, f"Expected password length 16, got {len(password)}"
    assert password.isalnum(), "Password is not alphanumeric"


def test_new_secrets_permissions():
    secrets_path = "/home/user/app/new_secrets.json"
    assert os.path.isfile(secrets_path), f"New secrets file missing at {secrets_path}"

    st = os.stat(secrets_path)
    permissions = stat.S_IMODE(st.st_mode)

    assert permissions == 0o600, f"Expected permissions 0600, got {oct(permissions)}"


def test_secure_rotate_script_executes_and_uses_secrets():
    script_path = "/home/user/app/secure_rotate.py"
    output_path = "/home/user/app/new_secrets.json"

    assert os.path.exists(script_path), f"Rotation script missing at {script_path}"
    assert stat.S_ISREG(os.lstat(script_path).st_mode), "Rotation script must be a regular file"

    with open(script_path, "r") as f:
        source = f.read()
    try:
        tree = ast.parse(source, filename=script_path)
    except SyntaxError as exc:
        pytest.fail(f"Rotation script is not valid Python: {exc}")

    module_aliases = set()
    imported_functions = set()
    star_import = False
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for name in node.names:
                if name.name == "secrets":
                    module_aliases.add(name.asname or "secrets")
        elif isinstance(node, ast.ImportFrom) and node.module == "secrets":
            for name in node.names:
                if name.name == "*":
                    star_import = True
                else:
                    imported_functions.add(name.asname or name.name)

    known_secret_calls = {
        "choice", "randbelow", "randbits", "token_bytes", "token_hex",
        "token_urlsafe", "compare_digest", "SystemRandom"
    }
    uses_secrets_call = any(
        isinstance(node, ast.Call)
        and (
            (
                isinstance(node.func, ast.Attribute)
                and isinstance(node.func.value, ast.Name)
                and node.func.value.id in module_aliases
            )
            or (isinstance(node.func, ast.Name) and node.func.id in imported_functions)
            or (star_import and isinstance(node.func, ast.Name) and node.func.id in known_secret_calls)
        )
        for node in ast.walk(tree)
    )
    assert module_aliases or imported_functions or star_import, "secure_rotate.py must import the secrets module"
    assert uses_secrets_call, "secure_rotate.py must call functionality imported from secrets"

    generated_passwords = []
    for _ in range(2):
        if os.path.lexists(output_path):
            os.unlink(output_path)

        result = subprocess.run(
            [sys.executable, script_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        assert result.returncode == 0, f"secure_rotate.py failed: {result.stderr}"
        assert os.path.exists(output_path), "secure_rotate.py did not create new_secrets.json"
        assert stat.S_ISREG(os.lstat(output_path).st_mode), "new_secrets.json must be a regular file"

        with open(output_path, "r") as f:
            try:
                data = json.load(f)
            except json.JSONDecodeError as exc:
                pytest.fail(f"Generated secrets file is not valid JSON: {exc}")

        assert "db_password" in data, "Generated JSON is missing db_password"
        password = data["db_password"]
        assert isinstance(password, str), "Generated password is not a string"
        assert len(password) == 16, f"Expected generated password length 16, got {len(password)}"
        assert password.isalnum(), "Generated password is not alphanumeric"
        assert stat.S_IMODE(os.stat(output_path).st_mode) == 0o600, "Generated file permissions are not 0600"
        generated_passwords.append(password)

    assert generated_passwords[0] != generated_passwords[1], "Repeated executions produced the same fixed password"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
