#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import json
import subprocess
import re
import shutil
import tempfile
import pytest


def test_rust_vulnerability_fixed():
    project = "/home/user/web_service"
    main_rs = os.path.join(project, "src/main.rs")
    assert os.path.isfile(main_rs), f"Missing {main_rs}"

    with open(main_rs, "r") as f:
        content = f.read()
        assert "Invalid filename" in content, "The Rust code does not contain the expected error message 'Invalid filename' for path traversal attempts."
        assert "/" in content or ".." in content, "The Rust code does not seem to check for '/' or '..'."

    # Preserve the original compilation and project-test assertion.
    result = subprocess.run(
        ["cargo", "test"],
        cwd=project,
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, f"cargo test failed:\n{result.stdout}\n{result.stderr}"

    # Exercise the submitted implementation with runtime-derived filenames.
    # A valid file must still be readable, while existing files whose names
    # contain either forbidden pattern must be rejected with the exact error.
    with tempfile.TemporaryDirectory(prefix="rust_verify_") as td:
        test_project = os.path.join(td, "web_service")
        shutil.copytree(project, test_project)
        copied_main = os.path.join(test_project, "src/main.rs")
        with open(copied_main, "a") as f:
            f.write(r'''

#[cfg(test)]
mod verifier_runtime_behavior {
    use super::*;
    use std::fs;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn valid_and_invalid_runtime_filenames() {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let token = format!("verifier_{}_{}", std::process::id(), nonce);
        let expected = format!("runtime-content-{}", token);

        fs::create_dir_all("/tmp/public_uploads").unwrap();
        fs::write(format!("/tmp/public_uploads/{}", token), &expected).unwrap();
        assert_eq!(read_user_file(&token), Ok(expected));

        let dotted = format!("{}..txt", token);
        fs::write(format!("/tmp/public_uploads/{}", dotted), "must-not-read").unwrap();
        assert_eq!(read_user_file(&dotted), Err("Invalid filename".to_string()));

        let directory = format!("dir_{}", token);
        let slashed = format!("{}/file.txt", directory);
        fs::create_dir_all(format!("/tmp/public_uploads/{}", directory)).unwrap();
        fs::write(format!("/tmp/public_uploads/{}", slashed), "must-not-read").unwrap();
        assert_eq!(read_user_file(&slashed), Err("Invalid filename".to_string()));
    }
}
''')

        behavior = subprocess.run(
            ["cargo", "test", "valid_and_invalid_runtime_filenames", "--", "--exact"],
            cwd=test_project,
            capture_output=True,
            text=True
        )
        assert behavior.returncode == 0, (
            "Runtime behavior tests failed:\n"
            + behavior.stdout + "\n" + behavior.stderr
        )
        assert "1 passed" in behavior.stdout, "The injected runtime behavior test did not execute."


def test_ssh_hardening():
    ssh_config = "/home/user/ssh_audit/sshd_config"
    assert os.path.isfile(ssh_config), f"Missing {ssh_config}"

    with open(ssh_config, "r") as f:
        content = f.read()

    assert re.search(r"(?m)^[ \t]*PermitRootLogin[ \t]+no[ \t]*$", content), "PermitRootLogin is not strictly set to 'no' in sshd_config."
    assert re.search(r"(?m)^[ \t]*PasswordAuthentication[ \t]+no[ \t]*$", content), "PasswordAuthentication is not strictly set to 'no' in sshd_config."


def test_ssh_key_permissions():
    ssh_key = "/home/user/ssh_keys/id_rsa"
    assert os.path.isfile(ssh_key), f"Missing {ssh_key}"

    file_stat = os.stat(ssh_key)
    permissions = stat.S_IMODE(file_stat.st_mode)
    assert permissions == 0o600, f"Expected permissions 0o600 for {ssh_key}, got {oct(permissions)}"


def test_audit_report():
    report_path = "/home/user/audit_report.json"
    assert os.path.isfile(report_path), f"Missing {report_path}"

    with open(report_path, "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{report_path} is not valid JSON.")

    assert report.get("identified_cwe") == "CWE-22", "identified_cwe must be exactly 'CWE-22'."
    assert report.get("ssh_root_login_fixed") is True, "ssh_root_login_fixed must be true."
    assert report.get("ssh_password_auth_fixed") is True, "ssh_password_auth_fixed must be true."
    assert report.get("key_permission_octal") == "0600", "key_permission_octal must be '0600'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
