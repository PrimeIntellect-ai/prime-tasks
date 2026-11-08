#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import os
import re
import subprocess
import tempfile
import uuid

CRT = "/home/user/certs/server.crt"
KEY = "/home/user/certs/server.key"
RULES = "/home/user/rules.conf"
SOURCE = "/home/user/src/data_proxy.cpp"
EXE = "/home/user/data_proxy"
ORIGINAL_INPUT = "/home/user/data/traffic.txt"
OUTPUT = "/home/user/output.log"


def run(command, **kwargs):
    return subprocess.run(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
        **kwargs,
    )


def assert_proxy_output(executable, input_path, output_path, expected_lines, env=None):
    if os.path.exists(output_path):
        os.unlink(output_path)
    result = run([executable, input_path, output_path], env=env)
    assert result.returncode == 0, (
        f"Proxy failed with status {result.returncode}.\n"
        f"stdout: {result.stdout.decode(errors='replace')}\n"
        f"stderr: {result.stderr.decode(errors='replace')}"
    )
    assert os.path.isfile(output_path), "The proxy did not create its requested output file."
    with open(output_path, "r", encoding="utf-8") as f:
        actual = f.read().splitlines()
    assert actual == expected_lines, f"Unexpected proxy output: {actual!r}"


def test_00_cpp_code_fixed_and_buffer_unchanged():
    assert os.path.isfile(SOURCE), f"The file {SOURCE} is missing."
    with open(SOURCE, "r", encoding="utf-8") as f:
        content = f.read()

    assert "strcpy(buffer, data.c_str());" not in content, \
        "The vulnerable strcpy function is still present in the C++ code."
    assert re.search(r"char\s+buffer\s*\[\s*64\s*\]", content), \
        "The required 64-byte buffer is missing or its size was changed."


def test_01_certs_are_valid_rsa2048_matching_and_365_days():
    assert os.path.isfile(CRT), f"The certificate file {CRT} is missing."
    assert os.path.isfile(KEY), f"The private key file {KEY} is missing."

    with open(CRT, "r", encoding="utf-8") as f:
        crt_content = f.read()
    assert "BEGIN CERTIFICATE" in crt_content, \
        "The server.crt file does not appear to be a valid PEM certificate."

    cert_check = run(["openssl", "x509", "-in", CRT, "-noout"])
    assert cert_check.returncode == 0, cert_check.stderr.decode(errors="replace")
    key_check = run(["openssl", "pkey", "-in", KEY, "-check", "-noout"])
    assert key_check.returncode == 0, key_check.stderr.decode(errors="replace")

    subject = subprocess.check_output(
        ["openssl", "x509", "-in", CRT, "-noout", "-subject", "-nameopt", "RFC2253"],
        text=True,
    ).strip()
    subject_value = subject.split("=", 1)[1] if "=" in subject else subject
    assert re.search(r"(^|,)CN=localhost($|,)", subject_value), \
        f"Certificate CN is not localhost: {subject}"

    cert_pub_pem = subprocess.check_output(["openssl", "x509", "-in", CRT, "-pubkey", "-noout"])
    cert_pub_text = subprocess.check_output(
        ["openssl", "pkey", "-pubin", "-text", "-noout"], input=cert_pub_pem
    ).decode(errors="replace")
    assert re.search(r"Public-Key:\s*\(2048 bit\)", cert_pub_text), \
        "The certificate does not contain an RSA-2048 public key."

    key_text = subprocess.check_output(
        ["openssl", "pkey", "-in", KEY, "-text", "-noout"]
    ).decode(errors="replace")
    assert re.search(r"Private-Key:\s*\(2048 bit", key_text), \
        "The private key is not RSA-2048."

    cert_pub_der = subprocess.check_output(
        ["openssl", "pkey", "-pubin", "-outform", "DER"], input=cert_pub_pem
    )
    key_pub_der = subprocess.check_output(
        ["openssl", "pkey", "-in", KEY, "-pubout", "-outform", "DER"]
    )
    assert cert_pub_der == key_pub_der, "The certificate and private key do not match."

    dates = subprocess.check_output(
        ["openssl", "x509", "-in", CRT, "-noout", "-dates"], text=True
    ).splitlines()
    values = dict(line.split("=", 1) for line in dates)
    fmt = "%b %d %H:%M:%S %Y %Z"
    not_before = datetime.datetime.strptime(values["notBefore"], fmt).replace(tzinfo=datetime.timezone.utc)
    not_after = datetime.datetime.strptime(values["notAfter"], fmt).replace(tzinfo=datetime.timezone.utc)
    now = datetime.datetime.now(datetime.timezone.utc)
    assert not_before <= now <= not_after, "The certificate is not currently valid."
    assert not_after - not_before == datetime.timedelta(days=365), \
        "The certificate validity period is not exactly 365 days."


def test_02_rules_conf_has_exactly_one_rule():
    assert os.path.isfile(RULES), f"The file {RULES} is missing."
    with open(RULES, "r", encoding="utf-8") as f:
        content = f.read().strip()
    assert "BLOCK=10.99.0.42" in content, \
        "The rules.conf file does not contain the correct BLOCK directive."
    assert content == "BLOCK=10.99.0.42", \
        "rules.conf must contain exactly one rule in the required format."


def test_03_executable_exists_and_is_compiled_program():
    assert os.path.isfile(EXE), f"The compiled executable {EXE} is missing."
    assert os.access(EXE, os.X_OK), f"The file {EXE} is not executable."
    with open(EXE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "data_proxy is not a compiled ELF executable."


def test_10_execute_submitted_binary_and_rebuilt_source():
    token = uuid.uuid4().hex
    allowed_ip = "198.51.100.17"
    second_ip = "203.0.113.29"
    short_payload = "SAFE_" + token
    long_payload = "LONG_" + token + "_" + ("Z" * 140)
    blocked_payload = "BLOCKED_" + token

    expected = [
        f"ALLOWED: {allowed_ip} - {short_payload}",
        f"ALLOWED: {second_ip} - {long_payload[:63]}",
    ]

    with tempfile.TemporaryDirectory() as td:
        custom_input = os.path.join(td, "traffic.txt")
        submitted_output = os.path.join(td, "submitted.log")
        rebuilt_output = os.path.join(td, "rebuilt.log")
        rebuilt_exe = os.path.join(td, "data_proxy_asan")

        with open(custom_input, "w", encoding="utf-8") as f:
            f.write(f"{allowed_ip} {short_payload}\n")
            f.write(f"10.99.0.42 {blocked_payload}\n")
            f.write(f"{second_ip} {long_payload}\n")

        assert_proxy_output(EXE, custom_input, submitted_output, expected)

        compile_result = run([
            "g++", "-fsanitize=address,undefined", "-fno-omit-frame-pointer",
            "-o", rebuilt_exe, SOURCE,
        ])
        assert compile_result.returncode == 0, (
            "The patched source does not compile:\n" +
            compile_result.stderr.decode(errors="replace")
        )
        asan_env = os.environ.copy()
        asan_env["ASAN_OPTIONS"] = "detect_leaks=0:halt_on_error=1"
        assert_proxy_output(rebuilt_exe, custom_input, rebuilt_output, expected, env=asan_env)

    original_expected = [
        "ALLOWED: 192.168.1.1 - NORMAL_PAYLOAD",
        "ALLOWED: 192.168.1.2 - THIS_IS_A_VERY_LONG_STRING_THAT_WILL_DEFINITELY_CAUSE_A_BUFFE",
        "ALLOWED: 10.0.0.5 - SHORT_DATA",
    ]
    assert_proxy_output(EXE, ORIGINAL_INPUT, OUTPUT, original_expected)


def test_20_output_log_exists_and_content():
    assert os.path.isfile(OUTPUT), \
        f"The file {OUTPUT} is missing. Did the application run successfully?"
    with open(OUTPUT, "r", encoding="utf-8") as f:
        content = f.read()

    assert "MALICIOUS_PAYLOAD_DROP_ME" not in content, \
        "The malicious payload was not dropped. Check rules.conf and firewall logic."
    assert "10.99.0.42" not in content, \
        "The blocked IP 10.99.0.42 was found in the output. It should have been blocked."
    assert "ALLOWED: 192.168.1.1 - NORMAL_PAYLOAD" in content, \
        "Normal payload is missing from the output log."
    assert "ALLOWED: 10.0.0.5 - SHORT_DATA" in content, \
        "Short data payload is missing from the output log."

    truncated_string = "THIS_IS_A_VERY_LONG_STRING_THAT_WILL_DEFINITELY_CAUSE_A_BUFFE"
    expected_long_line = f"ALLOWED: 192.168.1.2 - {truncated_string}"
    assert expected_long_line in content, \
        "The long string was not properly truncated to fit within the 64-byte buffer (63 chars + null)."
    assert "BUFFER_OVERFLOW" not in content, \
        "The long string seems to have overflowed or wasn't truncated correctly."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
