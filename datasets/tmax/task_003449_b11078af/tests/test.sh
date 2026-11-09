#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import secrets
import subprocess
import tempfile

CPP_FILE = "/home/user/cookie_extractor.cpp"
LOG_FILE = "/home/user/audit/http_logs.txt"
OUTPUT_FILE = "/home/user/admin_ips.txt"
TARGET_BINARY = "/home/user/audit/target_binary"
SYS_ROOT = "/home/user/audit/sys_files"


def read_nonempty_lines(path):
    with open(path, "r") as f:
        return [line.strip() for line in f.readlines() if line.strip()]


def compile_extractor():
    fd, executable = tempfile.mkstemp(prefix="cookie_extractor_", dir="/tmp")
    os.close(fd)
    os.unlink(executable)
    subprocess.run(
        ["g++", "-std=c++17", CPP_FILE, "-o", executable],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert os.path.isfile(executable), "Compilation did not produce an executable."
    return executable


def run_extractor(executable):
    subprocess.run(
        [executable],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert os.path.isfile(OUTPUT_FILE), f"Expected output file {OUTPUT_FILE} does not exist."
    return read_nonempty_lines(OUTPUT_FILE)


def extract_token_from_binary():
    with open(TARGET_BINARY, "rb") as f:
        binary = f.read()
    matches = re.findall(rb"X-Admin-Token: [A-Za-z0-9_]+", binary)
    assert matches, "The admin token could not be found in target_binary."
    return matches[0].decode("ascii")


def random_ip(prefix):
    return f"{prefix}.{secrets.randbelow(254) + 1}.{secrets.randbelow(254) + 1}.{secrets.randbelow(254) + 1}"


def test_cookie_extractor_cpp_exists():
    assert os.path.isfile(CPP_FILE), f"Expected C++ source file {CPP_FILE} does not exist."
    with open(CPP_FILE, "r") as f:
        content = f.read()
    assert len(content.strip()) > 0, f"File {CPP_FILE} exists but is empty."
    assert "#include" in content or "int main" in content, f"File {CPP_FILE} does not appear to contain valid C++ code."


def test_admin_ips_output_generated_by_cpp():
    executable = compile_extractor()
    try:
        lines = run_extractor(executable)
    finally:
        if os.path.exists(executable):
            os.unlink(executable)

    expected_ips = ["192.168.1.15", "172.16.4.102"]
    assert lines == expected_ips, f"Contents of {OUTPUT_FILE} are incorrect. Expected {expected_ips}, but got {lines}."


def test_cookie_extractor_on_derived_input():
    token = extract_token_from_binary()
    positive_one = random_ip(11)
    negative = random_ip(12)
    positive_two = random_ip(13)
    altered_token = token[:-1] + ("0" if token[-1] != "0" else "1")

    generated_log = f"""IP: {positive_one}
GET /generated-one HTTP/1.1
Host: verifier.local
Cookie: session_id=random-a; {token}

IP: {negative}
GET /generated-negative HTTP/1.1
Host: verifier.local
Cookie: session_id=random-b; {altered_token}

IP: {positive_two}
POST /generated-two HTTP/1.1
Host: verifier.local
Cookie: {token}; region=test
"""

    with open(LOG_FILE, "rb") as f:
        original_log = f.read()
    original_output = None
    if os.path.isfile(OUTPUT_FILE):
        with open(OUTPUT_FILE, "rb") as f:
            original_output = f.read()

    executable = compile_extractor()
    try:
        with open(LOG_FILE, "w") as f:
            f.write(generated_log)
        lines = run_extractor(executable)
        expected = [positive_one, positive_two]
        assert lines == expected, f"Extractor failed generated input. Expected {expected}, but got {lines}."
    finally:
        with open(LOG_FILE, "wb") as f:
            f.write(original_log)
        if original_output is None:
            if os.path.exists(OUTPUT_FILE):
                os.unlink(OUTPUT_FILE)
        else:
            with open(OUTPUT_FILE, "wb") as f:
                f.write(original_output)
        if os.path.exists(executable):
            os.unlink(executable)


def test_vuln_file_output():
    vuln_file = "/home/user/vuln_file.txt"
    assert os.path.isfile(vuln_file), f"Expected output file {vuln_file} does not exist."
    with open(vuln_file, "r") as f:
        content = f.read().strip()

    assert os.path.isabs(content), "The vulnerable file path must be absolute."
    normalized = os.path.abspath(content)
    assert os.path.commonpath([normalized, SYS_ROOT]) == SYS_ROOT, f"Path '{content}' is not under {SYS_ROOT}."
    assert os.path.isfile(normalized), f"Path '{content}' is not an existing regular file."
    mode = os.stat(normalized).st_mode
    assert stat.S_ISREG(mode), f"Path '{content}' is not a regular file."
    assert mode & stat.S_IWOTH, f"Path '{content}' is not world-writable."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
