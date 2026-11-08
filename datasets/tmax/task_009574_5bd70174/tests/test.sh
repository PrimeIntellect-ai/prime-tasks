#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import tempfile


def test_ssh_config_hardened():
    config_path = "/home/user/target_sshd_config"
    assert os.path.exists(config_path), f"Missing file: {config_path}"

    with open(config_path, "r") as f:
        content = f.read()

    assert "PermitRootLogin no" in content, "PermitRootLogin was not changed to 'no'"
    assert "PasswordAuthentication no" in content, "PasswordAuthentication was not changed to 'no'"

    assert "PermitRootLogin yes" not in content, "PermitRootLogin 'yes' is still present"
    assert "PasswordAuthentication yes" not in content, "PasswordAuthentication 'yes' is still present"


def test_encrypted_report_exists_and_valid():
    report_path = "/home/user/report.enc"
    key_path = "/home/user/aes_key.txt"

    assert os.path.exists(report_path), f"Missing encrypted report: {report_path}"
    assert os.path.exists(key_path), f"Missing key file: {key_path}"

    with open(key_path, "r") as f:
        hex_key = f.read().strip()

    assert len(hex_key) == 64, "AES key should be 64 hex characters"

    cmd = [
        "openssl", "enc", "-d", "-aes-256-cbc",
        "-in", report_path,
        "-K", hex_key,
        "-iv", "00000000000000000000000000000000"
    ]

    result = subprocess.run(cmd, capture_output=True, text=True)

    assert result.returncode == 0, f"Failed to decrypt the report. OpenSSL error: {result.stderr}"

    expected_json = '{"vulnerabilities":["PermitRootLogin","PasswordAuthentication"]}'
    assert result.stdout == expected_json, f"Decrypted JSON does not match expected output. Got: {result.stdout}"


def decrypt_report(path, hex_key):
    result = subprocess.run(
        [
            "openssl", "enc", "-d", "-aes-256-cbc",
            "-in", path,
            "-K", hex_key,
            "-iv", "00000000000000000000000000000000",
        ],
        capture_output=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"Scanner output could not be decrypted: {result.stderr.decode(errors='replace')}"
    )
    return result.stdout


def exercise_scanner(scanner_path, workdir):
    cases = [
        (
            "none",
            "#PermitRootLogin yes\n#PasswordAuthentication yes\n"
            "PermitRootLogin no\nPasswordAuthentication no\n"
            "PermitRootLogin yes extra\nPasswordAuthentication yes extra\n",
            b'{"vulnerabilities":[]}',
        ),
        (
            "root_only",
            "Port 22\nPermitRootLogin yes\n#PasswordAuthentication yes\n",
            b'{"vulnerabilities":["PermitRootLogin"]}',
        ),
        (
            "password_only",
            "Port 2200\n#PermitRootLogin yes\nPasswordAuthentication yes\n",
            b'{"vulnerabilities":["PasswordAuthentication"]}',
        ),
        (
            "both_reversed",
            "PasswordAuthentication yes\nListenAddress 127.0.0.1\nPermitRootLogin yes\n",
            b'{"vulnerabilities":["PermitRootLogin","PasswordAuthentication"]}',
        ),
    ]

    for name, config, expected in cases:
        config_path = os.path.join(workdir, name + ".conf")
        report_path = os.path.join(workdir, name + ".enc")
        hex_key = os.urandom(32).hex()
        with open(config_path, "w") as f:
            f.write(config)

        result = subprocess.run(
            [scanner_path, config_path, report_path, hex_key],
            capture_output=True,
            timeout=10,
        )
        assert result.returncode == 0, (
            f"Scanner failed for case {name}: {result.stderr.decode(errors='replace')}"
        )
        assert os.path.isfile(report_path), f"Scanner did not create output for case {name}"
        actual = decrypt_report(report_path, hex_key)
        assert actual == expected, f"Wrong JSON for case {name}: {actual!r}"


def test_scanner_source_binary_and_behavior():
    source_path = "/home/user/scanner.c"
    scanner_path = "/home/user/scanner"

    assert os.path.lexists(source_path), f"Missing source file: {source_path}"
    assert stat.S_ISREG(os.lstat(source_path).st_mode), "scanner.c must be a regular file"
    assert os.path.lexists(scanner_path), f"Missing compiled scanner: {scanner_path}"
    scanner_stat = os.lstat(scanner_path)
    assert stat.S_ISREG(scanner_stat.st_mode), "scanner must be a regular file"
    assert scanner_stat.st_mode & 0o111, "scanner is not executable"
    with open(scanner_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "scanner is not a compiled ELF executable"

    with tempfile.TemporaryDirectory(prefix="scanner_verify_") as workdir:
        rebuilt_path = os.path.join(workdir, "scanner_rebuilt")
        build = subprocess.run(
            ["gcc", source_path, "-o", rebuilt_path, "-lcrypto"],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert build.returncode == 0, f"scanner.c failed to compile: {build.stderr}"

        installed_cases = os.path.join(workdir, "installed")
        rebuilt_cases = os.path.join(workdir, "rebuilt")
        os.mkdir(installed_cases)
        os.mkdir(rebuilt_cases)
        exercise_scanner(scanner_path, installed_cases)
        exercise_scanner(rebuilt_path, rebuilt_cases)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
