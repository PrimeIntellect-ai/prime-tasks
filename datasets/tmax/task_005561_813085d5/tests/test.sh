#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import subprocess
from pathlib import Path


def test_flagged_ips_content():
    """Keep the original final-state assertion for flagged IPs."""
    flagged_ips_file = Path("/home/user/flagged_ips.txt")
    assert flagged_ips_file.is_file(), f"File not found: {flagged_ips_file}. The C++ program may not have created it."

    content = flagged_ips_file.read_text().strip().splitlines()
    actual_ips = set(line.strip() for line in content if line.strip())
    expected_ips = {"192.168.1.100", "172.16.0.50", "10.0.0.12"}

    assert actual_ips == expected_ips, f"flagged_ips.txt does not contain the correct IPs. Expected {expected_ips}, but got {actual_ips}"
    assert len(content) == len(expected_ips), "flagged_ips.txt contains duplicate entries or extra lines."


def test_weak_certs_content():
    """Keep the original final-state assertion for weak certificates."""
    weak_certs_file = Path("/home/user/weak_certs.txt")
    assert weak_certs_file.is_file(), f"File not found: {weak_certs_file}. The bash script may not have created it."

    content = weak_certs_file.read_text().strip().splitlines()
    actual_certs = set(line.strip() for line in content if line.strip())
    expected_certs = {
        "/home/user/certs/cert_expired.pem",
        "/home/user/certs/cert_weak.pem",
    }

    assert actual_certs == expected_certs, f"weak_certs.txt does not contain the correct certificate paths. Expected {expected_certs}, but got {actual_certs}"
    assert len(content) == len(expected_certs), "weak_certs.txt contains duplicate entries or extra lines."


def test_authorized_keys_hardened():
    """Keep the original final-state assertion for authorized_keys."""
    auth_keys_file = Path("/home/user/.ssh/authorized_keys")
    assert auth_keys_file.is_file(), f"File not found: {auth_keys_file}"

    content = auth_keys_file.read_text().strip().splitlines()
    actual_entries = [line.strip() for line in content if line.strip()]
    expected_safe_identifiers = ["user@10.0.0.5", "user@10.0.0.8"]
    flagged_identifiers = ["192.168.1.100", "172.16.0.50", "10.0.0.12"]

    for entry in actual_entries:
        for flagged in flagged_identifiers:
            assert flagged not in entry, f"Found flagged IP {flagged} in authorized_keys. The file was not properly sanitized."

    found_safe_count = 0
    for entry in actual_entries:
        for safe in expected_safe_identifiers:
            if safe in entry:
                found_safe_count += 1

    assert found_safe_count == len(expected_safe_identifiers), f"authorized_keys is missing expected safe keys. Expected to find entries for {expected_safe_identifiers}."
    assert len(actual_entries) == len(expected_safe_identifiers), "authorized_keys contains unexpected extra entries."


def read_nonempty_lines(path):
    return [line.strip() for line in Path(path).read_text().splitlines() if line.strip()]


def assert_matcher_result(expected):
    output = Path("/home/user/flagged_ips.txt")
    assert output.is_file(), "Matcher did not create flagged_ips.txt"
    lines = read_nonempty_lines(output)
    assert set(lines) == expected, f"Matcher returned {set(lines)}, expected {expected}"
    assert len(lines) == len(expected), "Matcher output contains duplicates or extra lines"


def test_artifacts_and_dynamic_behavior(tmp_path):
    cpp = Path("/home/user/ids_matcher.cpp")
    matcher = Path("/home/user/ids_matcher")
    script = Path("/home/user/secure_env.sh")

    assert cpp.is_file(), "ids_matcher.cpp is missing"
    assert matcher.is_file(), "Compiled ids_matcher is missing"
    assert os.access(matcher, os.X_OK), "Compiled ids_matcher is not executable"
    assert script.is_file(), "secure_env.sh is missing"

    token = secrets.token_hex(10)
    sig1 = "SIG_" + token
    sig2 = "EVIL_" + token[::-1]
    ip1 = f"198.18.{secrets.randbelow(200) + 1}.{secrets.randbelow(200) + 1}"
    ip2 = f"198.19.{secrets.randbelow(200) + 1}.{secrets.randbelow(200) + 1}"
    safe_ip = f"203.0.113.{secrets.randbelow(200) + 1}"

    Path("/home/user/signatures.txt").write_text(f"{sig1}\n{sig2}\n")
    Path("/home/user/traffic.log").write_text(
        f"1800000000 {ip1} 443 prefix-{sig1}-suffix\n"
        f"1800000001 {safe_ip} 80 harmless-{token}\n"
        f"1800000002 {ip2} 22 text containing {sig2} here\n"
        f"1800000003 {ip1} 8080 repeated {sig2}\n"
    )
    expected_ips = {ip1, ip2}

    subprocess.run([str(matcher)], check=True, timeout=20)
    assert_matcher_result(expected_ips)

    rebuilt = tmp_path / "ids_matcher_rebuilt"
    subprocess.run(
        ["g++", "-std=c++17", str(cpp), "-o", str(rebuilt)],
        check=True,
        timeout=60,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    Path("/home/user/flagged_ips.txt").unlink(missing_ok=True)
    subprocess.run([str(rebuilt)], check=True, timeout=20)
    assert_matcher_result(expected_ips)

    cert_dir = Path("/home/user/certs")
    shutil.rmtree(cert_dir)
    cert_dir.mkdir(parents=True)
    cert_token = secrets.token_hex(8)
    good_cert = cert_dir / f"good_{cert_token}.pem"
    weak_cert = cert_dir / f"weak_{cert_token}.pem"
    expired_cert = cert_dir / f"expired_{cert_token}.pem"

    def make_cert(output, key_bits, days, subject, faketime=None):
        key = tmp_path / (output.stem + ".key")
        command = [
            "openssl", "req", "-x509", "-newkey", f"rsa:{key_bits}",
            "-keyout", str(key), "-out", str(output), "-days", str(days),
            "-nodes", "-subj", f"/CN={subject}",
        ]
        if faketime is not None:
            command = ["faketime", faketime] + command
        subprocess.run(command, check=True, timeout=60, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    make_cert(good_cert, 2048, 30, "good-" + cert_token)
    make_cert(weak_cert, 1024, 30, "weak-" + cert_token)
    make_cert(expired_cert, 2048, 1, "expired-" + cert_token, "2020-01-01 00:00:00")

    assert subprocess.run(["openssl", "x509", "-in", str(good_cert), "-noout", "-checkend", "0"]).returncode == 0
    assert subprocess.run(["openssl", "x509", "-in", str(expired_cert), "-noout", "-checkend", "0"]).returncode != 0

    flag1 = f"100.64.{secrets.randbelow(200) + 1}.{secrets.randbelow(200) + 1}"
    flag2 = f"100.65.{secrets.randbelow(200) + 1}.{secrets.randbelow(200) + 1}"
    Path("/home/user/flagged_ips.txt").write_text(f"{flag1}\n{flag2}\n")

    safe_line = f"ssh-rsa SAFE{token} trusted@203.0.113.10"
    embedded_line = f"ssh-rsa EMBED{token} note-{flag1}-not-trailing"
    remove_at_line = f"ssh-rsa BADAT{token} attacker@{flag1}"
    remove_exact_line = f"ssh-rsa BADEXACT{token} {flag2}"
    auth = Path("/home/user/.ssh/authorized_keys")
    auth.write_text("\n".join([safe_line, remove_at_line, embedded_line, remove_exact_line]) + "\n")

    subprocess.run(["bash", str(script)], check=True, timeout=60)

    weak_lines = read_nonempty_lines("/home/user/weak_certs.txt")
    expected_weak = {str(weak_cert), str(expired_cert)}
    assert set(weak_lines) == expected_weak, f"Certificate scan returned {set(weak_lines)}, expected {expected_weak}"
    assert len(weak_lines) == len(expected_weak), "Certificate scan contains duplicate or extra paths"

    remaining = read_nonempty_lines(auth)
    assert remaining == [safe_line, embedded_line], f"SSH hardening produced unexpected entries: {remaining}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
