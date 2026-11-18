#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile
from pathlib import Path

import pytest

TASK_DIR = Path("/home/user/audit_task")
SOURCE = TASK_DIR / "audit_processor.cpp"


@pytest.fixture(scope="session")
def compiled_processor(tmp_path_factory):
    assert SOURCE.is_file(), f"Required source file {SOURCE} is missing."
    build_dir = tmp_path_factory.mktemp("build")
    executable = build_dir / "audit_processor"
    result = subprocess.run(
        ["g++", "-std=c++17", str(SOURCE), "-o", str(executable), "-lssl", "-lcrypto"],
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, (
        f"audit_processor.cpp failed to compile.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert executable.is_file() and os.access(executable, os.X_OK)
    return executable


def test_report_exists_and_correct():
    report_path = "/home/user/audit_task/audit_report.txt"
    assert os.path.isfile(report_path), f"Report file {report_path} is missing."

    with open(report_path, "r") as f:
        content = f.read().strip()

    expected_content = (
        "Total lines: 6\n"
        "Redacted lines: 3\n"
        "Intrusions detected: 2"
    )

    assert content == expected_content, f"Report content is incorrect. Expected:\n{expected_content}\nGot:\n{content}"


def test_encrypted_log_exists_and_decrypts():
    enc_path = "/home/user/audit_task/secure_audit.enc"
    key_path = "/home/user/audit_task/key.bin"
    iv_path = "/home/user/audit_task/iv.bin"

    assert os.path.isfile(enc_path), f"Encrypted log {enc_path} is missing."
    assert os.path.isfile(key_path), f"Key file {key_path} is missing."
    assert os.path.isfile(iv_path), f"IV file {iv_path} is missing."

    with open(key_path, "rb") as f:
        hex_key = f.read().hex().upper()

    with open(iv_path, "rb") as f:
        hex_iv = f.read().hex().upper()

    decrypted_path = "/home/user/audit_task/decrypted_audit.log"

    cmd = [
        "openssl", "enc", "-aes-256-cbc", "-d",
        "-in", enc_path,
        "-out", decrypted_path,
        "-K", hex_key,
        "-iv", hex_iv
    ]

    result = subprocess.run(cmd, capture_output=True)
    assert result.returncode == 0, f"Failed to decrypt {enc_path}. OpenSSL error: {result.stderr.decode()}"
    assert os.path.isfile(decrypted_path), "Decrypted output file was not created."

    with open(decrypted_path, "r") as f:
        decrypted_content = f.read()

    expected_lines = [
        '192.168.1.10 - - [10/Oct/2023:13:55:36 -0700] "GET /login?token=[REDACTED] HTTP/1.1" 200 2326',
        '10.0.0.5 - - [10/Oct/2023:13:56:10 -0700] "GET /product?id=1\' OR \'1\'=\'1 HTTP/1.1" 500 503',
        '172.16.0.4 - - [10/Oct/2023:13:57:00 -0700] "POST /checkout?cc=[REDACTED]&item=5 HTTP/1.1" 200 405',
        '192.168.1.11 - - [10/Oct/2023:13:58:12 -0700] "GET /../../../../etc/passwd HTTP/1.1" 403 125',
        '10.1.1.1 - - [10/Oct/2023:13:59:00 -0700] "GET /index.html HTTP/1.1" 200 1024',
        '192.168.1.10 - - [10/Oct/2023:14:00:00 -0700] "GET /dashboard?token=[REDACTED]&cc=[REDACTED] HTTP/1.1" 200 2326'
    ]

    decrypted_lines = decrypted_content.strip().split('\n')
    assert len(decrypted_lines) == len(expected_lines), f"Decrypted log has {len(decrypted_lines)} lines, expected {len(expected_lines)}."

    for i, (actual, expected) in enumerate(zip(decrypted_lines, expected_lines)):
        assert actual == expected, f"Line {i+1} mismatch.\nExpected: {expected}\nGot: {actual}"


def redact_line(line):
    line, cc_count = re.subn(r"cc=\d{16}(?!\d)", "cc=[REDACTED]", line)
    line, token_count = re.subn(r"token=[A-Za-z0-9]+", "token=[REDACTED]", line)
    return line, (cc_count + token_count > 0)


def test_compiled_program_processes_fresh_input(compiled_processor):
    marker = secrets.token_hex(10)
    token = secrets.token_hex(9)
    card = "".join(str(secrets.randbelow(10)) for _ in range(16))
    lines = [
        f"host-{marker} GET /ordinary HTTP/1.1",
        f"host-a GET /account?token={token}&mode=view HTTP/1.1",
        f"host-b POST /pay?cc={card}&item={marker} HTTP/1.1",
        f"host-c GET /search?q=x' OR '1'='1&token={token}-tail HTTP/1.1",
        f"host-d GET /safe/../private/{marker} HTTP/1.1",
        f"host-e POST /both?token={token}&cc={card} HTTP/1.1",
        "host-f GET /empty?token=&cc=123456789012345 HTTP/1.1",
    ]

    expected_lines = []
    redacted_count = 0
    intrusion_count = 0
    for line in lines:
        redacted, changed = redact_line(line)
        expected_lines.append(redacted)
        redacted_count += int(changed)
        intrusion_count += int("../" in line or "' OR '1'='1" in line)

    with tempfile.TemporaryDirectory(prefix="audit-runtime-") as work:
        work = Path(work)
        input_path = work / f"input-{marker}.log"
        encrypted_path = work / f"encrypted-{marker}.bin"
        report_path = work / f"report-{marker}.txt"
        decrypted_path = work / f"decrypted-{marker}.txt"
        key = os.urandom(32)
        iv = os.urandom(16)
        (work / "key.bin").write_bytes(key)
        (work / "iv.bin").write_bytes(iv)
        input_path.write_text("\n".join(lines) + "\n")

        result = subprocess.run(
            [str(compiled_processor), str(input_path), str(encrypted_path), str(report_path)],
            cwd=work,
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, (
            f"Processor failed on fresh input.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert encrypted_path.is_file(), "Processor did not create the requested encrypted output."
        assert report_path.is_file(), "Processor did not create the requested report."

        expected_report = (
            f"Total lines: {len(lines)}\n"
            f"Redacted lines: {redacted_count}\n"
            f"Intrusions detected: {intrusion_count}"
        )
        assert report_path.read_text().strip() == expected_report

        decrypt = subprocess.run(
            [
                "openssl", "enc", "-aes-256-cbc", "-d",
                "-in", str(encrypted_path),
                "-out", str(decrypted_path),
                "-K", key.hex().upper(),
                "-iv", iv.hex().upper(),
            ],
            cwd=work,
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert decrypt.returncode == 0, f"Fresh output could not be decrypted: {decrypt.stderr}"
        assert decrypted_path.read_text().splitlines() == expected_lines


def test_program_requires_exactly_three_arguments(compiled_processor):
    with tempfile.TemporaryDirectory(prefix="audit-args-") as work:
        work = Path(work)
        (work / "key.bin").write_bytes(os.urandom(32))
        (work / "iv.bin").write_bytes(os.urandom(16))
        input_path = work / "input.log"
        input_path.write_text("ordinary line\n")
        output_path = work / "output.enc"
        report_path = work / "report.txt"

        invocations = [
            [str(compiled_processor)],
            [str(compiled_processor), str(input_path), str(output_path)],
            [str(compiled_processor), str(input_path), str(output_path), str(report_path), "extra"],
        ]
        for command in invocations:
            result = subprocess.run(command, cwd=work, capture_output=True, timeout=10)
            assert result.returncode != 0, f"Program accepted an invalid argument count: {command}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
