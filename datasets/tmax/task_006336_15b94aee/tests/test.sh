#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import stat
import subprocess
import uuid
import pytest

HOME = "/home/user"
SOURCE = f"{HOME}/inspector.cpp"
BINARY = f"{HOME}/inspector"
REQUESTS = f"{HOME}/requests"
UPLOADS = f"{HOME}/uploads"
ALLOWED = f"{HOME}/allowed_ips.txt"
FIREWALL = f"{HOME}/firewall.log"
TRAFFIC = f"{HOME}/traffic.log"


def reset_outputs():
    for path in (FIREWALL, TRAFFIC):
        if os.path.lexists(path):
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            else:
                os.unlink(path)
    if os.path.lexists(UPLOADS):
        if os.path.isdir(UPLOADS) and not os.path.islink(UPLOADS):
            shutil.rmtree(UPLOADS)
        else:
            os.unlink(UPLOADS)
    os.makedirs(UPLOADS)


def write_request(path, ip, filename, body):
    with open(path, "w") as f:
        f.write(f"IP: {ip}\nFilename: {filename}\nBody: {body}\n")


def decrypt(path):
    result = subprocess.run(
        [
            "openssl", "enc", "-aes-256-cbc", "-d",
            "-in", path,
            "-K", "4B" * 32,
            "-iv", "56" * 16,
        ],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, result.stderr
    return result.stdout


@pytest.fixture(scope="session", autouse=True)
def build_and_run_baseline():
    info = os.lstat(SOURCE)
    assert stat.S_ISREG(info.st_mode), f"{SOURCE} must be a regular C++ source file"

    compile_result = subprocess.run(
        ["g++", "-std=c++17", SOURCE, "-o", BINARY, "-lcrypto"],
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert compile_result.returncode == 0, (
        f"Failed to compile {SOURCE}:\n{compile_result.stdout}\n{compile_result.stderr}"
    )
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK)

    if os.path.lexists(REQUESTS):
        if os.path.isdir(REQUESTS) and not os.path.islink(REQUESTS):
            shutil.rmtree(REQUESTS)
        else:
            os.unlink(REQUESTS)
    os.makedirs(REQUESTS)

    with open(ALLOWED, "w") as f:
        f.write("192.168.1.10\n10.0.0.5\n127.0.0.1\n")
    write_request(
        os.path.join(REQUESTS, "req1.txt"),
        "192.168.1.10",
        "../../etc/malicious.sh",
        "The user purchased an item with CC: 1234-5678-9012-3456 today.",
    )
    write_request(
        os.path.join(REQUESTS, "req2.txt"),
        "192.168.1.99",
        "harmless.txt",
        "This IP is not allowed. CC: 1111-2222-3333-4444.",
    )
    write_request(
        os.path.join(REQUESTS, "req3.txt"),
        "10.0.0.5",
        r"C:\Windows\System32\cmd.exe",
        "Valid payload without CC.",
    )

    reset_outputs()
    result = subprocess.run(
        [BINARY, REQUESTS], capture_output=True, text=True, timeout=30, cwd=HOME
    )
    assert result.returncode == 0, (
        f"Inspector failed on the supplied requests:\n{result.stdout}\n{result.stderr}"
    )
    yield


def test_firewall_log_contents():
    log_path = "/home/user/firewall.log"
    assert os.path.exists(log_path), f"Firewall log was not created at {log_path}"

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 1, f"Expected exactly 1 blocked request in firewall.log, but found {len(lines)}."
    assert lines[0] == "BLOCKED: 192.168.1.99", f"Expected 'BLOCKED: 192.168.1.99' in firewall.log, got '{lines[0]}'."


def test_traffic_log_contents():
    log_path = "/home/user/traffic.log"
    assert os.path.exists(log_path), f"Traffic log was not created at {log_path}"

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = {
        "[192.168.1.10] [malicious.sh] The user purchased an item with CC: XXXX-XXXX-XXXX-XXXX today.",
        "[10.0.0.5] [cmd.exe] Valid payload without CC."
    }

    assert len(lines) == 2, f"Expected exactly 2 processed requests in traffic.log, but found {len(lines)}."

    actual_lines_set = set(lines)
    missing = expected_lines - actual_lines_set
    unexpected = actual_lines_set - expected_lines

    assert actual_lines_set == expected_lines, (
        f"Traffic log contents are incorrect.\n"
        f"Missing expected lines: {missing}\n"
        f"Unexpected lines found: {unexpected}"
    )


def test_encrypted_payloads():
    uploads_dir = "/home/user/uploads"
    assert os.path.isdir(uploads_dir), f"Uploads directory does not exist at {uploads_dir}"

    expected_files = {
        "malicious.sh.enc": "The user purchased an item with CC: XXXX-XXXX-XXXX-XXXX today.",
        "cmd.exe.enc": "Valid payload without CC."
    }

    key_hex = "4B" * 32
    iv_hex = "56" * 16

    for fname, expected_text in expected_files.items():
        fpath = os.path.join(uploads_dir, fname)
        assert os.path.exists(fpath), f"Expected encrypted file {fpath} was not found. Check path traversal prevention and file naming."

        cmd = [
            "openssl", "enc", "-aes-256-cbc", "-d",
            "-in", fpath,
            "-K", key_hex,
            "-iv", iv_hex
        ]

        result = subprocess.run(cmd, capture_output=True, text=True)

        assert result.returncode == 0, (
            f"Failed to decrypt {fname}. Ensure it was encrypted with AES-256-CBC, "
            f"key='K'*32, iv='V'*16.\nOpenSSL Error: {result.stderr}"
        )

        decrypted_text = result.stdout
        assert decrypted_text == expected_text, (
            f"Decrypted content for {fname} does not match expected text.\n"
            f"Expected: {expected_text}\n"
            f"Got: {decrypted_text}\n"
            f"Ensure redaction happens BEFORE encryption."
        )


def test_runtime_generated_requests():
    token = uuid.uuid4().hex
    ip1 = f"198.51.100.{1 + int(token[:2], 16) % 200}"
    ip2 = f"192.0.2.{1 + int(token[2:4], 16) % 200}"
    blocked_ip = f"203.0.113.{1 + int(token[4:6], 16) % 200}"
    base1 = f"report_{token[:10]}.dat"
    base2 = f"capture_{token[10:20]}.bin"
    blocked_base = f"blocked_{token[20:28]}.dat"
    ignored_base = f"ignored_{token[28:]}.bin"

    body1 = f"runtime-{token} cards 4821-7390-1256-9044 and 1111-2222-3333-4444"
    body2 = f"payload-{token}-without-a-card"
    blocked_body = f"forbidden-{token}-5555-6666-7777-8888"
    expected1 = re.sub(r"\d{4}-\d{4}-\d{4}-\d{4}", "XXXX-XXXX-XXXX-XXXX", body1)
    expected2 = body2

    dynamic_dir = f"/tmp/requests_{token}"
    os.makedirs(dynamic_dir)
    write_request(os.path.join(dynamic_dir, "alpha.txt"), ip1, f"../../private/{base1}", body1)
    write_request(os.path.join(dynamic_dir, "beta.txt"), ip2, f"C:\\temp\\nested\\{base2}", body2)
    write_request(os.path.join(dynamic_dir, "blocked.txt"), blocked_ip, f"../{blocked_base}", blocked_body)
    write_request(os.path.join(dynamic_dir, "not-a-request.bin"), ip1, ignored_base, "must be ignored")

    with open(ALLOWED, "w") as f:
        f.write(f"{ip1}\n{ip2}\n")
    reset_outputs()
    with open(FIREWALL, "w") as f:
        f.write("KEEP-FIREWALL\n")
    with open(TRAFFIC, "w") as f:
        f.write("KEEP-TRAFFIC\n")

    result = subprocess.run(
        [BINARY, dynamic_dir], capture_output=True, text=True, timeout=30, cwd=HOME
    )
    assert result.returncode == 0, (
        f"Inspector failed on runtime-generated requests:\n{result.stdout}\n{result.stderr}"
    )

    with open(FIREWALL) as f:
        firewall_lines = [line.strip() for line in f if line.strip()]
    assert firewall_lines == ["KEEP-FIREWALL", f"BLOCKED: {blocked_ip}"]

    with open(TRAFFIC) as f:
        traffic_lines = [line.strip() for line in f if line.strip()]
    assert traffic_lines[0] == "KEEP-TRAFFIC"
    assert set(traffic_lines[1:]) == {
        f"[{ip1}] [{base1}] {expected1}",
        f"[{ip2}] [{base2}] {expected2}",
    }
    assert len(traffic_lines) == 3

    assert os.path.isdir(UPLOADS)
    assert set(os.listdir(UPLOADS)) == {f"{base1}.enc", f"{base2}.enc"}
    assert decrypt(os.path.join(UPLOADS, f"{base1}.enc")) == expected1
    assert decrypt(os.path.join(UPLOADS, f"{base2}.enc")) == expected2
    assert not os.path.exists(os.path.join(UPLOADS, f"{blocked_base}.enc"))
    assert not os.path.exists(os.path.join(UPLOADS, f"{ignored_base}.enc"))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
