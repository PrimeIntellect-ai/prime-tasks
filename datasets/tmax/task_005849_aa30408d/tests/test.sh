#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import os
import re
import secrets
import subprocess
import tempfile

EXPECTED_TOKEN = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4"
SOURCE = "/home/user/src/main.cpp"
BINARY = "/home/user/patched_processor"
RAW_LOG = "/home/user/raw.log"
CLEAN_LOG = "/home/user/clean.log"

SSN_RE = re.compile(r"(?<!\d)\d{3}-\d{2}-\d{4}(?!\d)")
CC_RE = re.compile(r"(?<!\d)(\d{12})(\d{4})(?!\d)")


def redact(line):
    line = SSN_RE.sub("***-**-****", line)
    return CC_RE.sub(lambda m: "************" + m.group(2), line)


def process_function_body(source):
    match = re.search(r"\bprocess_line\s*\([^)]*\)\s*\{", source)
    assert match, "process_line function was not found in main.cpp."
    start = source.find("{", match.start())
    depth = 0
    for pos in range(start, len(source)):
        if source[pos] == "{":
            depth += 1
        elif source[pos] == "}":
            depth -= 1
            if depth == 0:
                return source[start + 1:pos]
    raise AssertionError("Could not parse process_line function body.")


def run_processor(executable, lines):
    with tempfile.TemporaryDirectory() as directory:
        input_path = os.path.join(directory, "input.log")
        output_path = os.path.join(directory, "output.log")
        with open(input_path, "w", encoding="utf-8", newline="") as stream:
            stream.write("\n".join(lines) + "\n")
        result = subprocess.run(
            [executable, input_path, output_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
        assert result.returncode == 0, (
            f"{executable} failed with status {result.returncode}: "
            + result.stderr.decode(errors="replace")
        )
        assert os.path.isfile(output_path), f"{executable} did not create its output file."
        with open(output_path, "r", encoding="utf-8", newline="") as stream:
            return stream.read()


def test_token_extracted():
    token_path = "/home/user/token.txt"
    assert os.path.isfile(token_path), f"{token_path} does not exist."
    with open(token_path, "rb") as stream:
        token_bytes = stream.read()
    assert token_bytes == EXPECTED_TOKEN.encode(), (
        f"Token in {token_path} is incorrect or contains extra whitespace."
    )

    assert os.path.isfile("/home/user/processor.elf"), "processor.elf is missing."
    with open("/home/user/processor.elf", "rb") as stream:
        assert stream.read(4) == b"\x7fELF", "processor.elf is not an ELF binary."
    result = subprocess.run(
        ["readelf", "-p", ".rodata", "/home/user/processor.elf"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, "processor.elf has no readable .rodata section."
    match = re.search(r"SECRET_TOKEN:([0-9a-fA-F]{32})", result.stdout)
    assert match, "The required token is not present in processor.elf's .rodata section."
    assert match.group(1).lower() == EXPECTED_TOKEN


def test_source_was_patched_and_compiles():
    assert os.path.isfile(SOURCE), f"{SOURCE} does not exist."
    with open(SOURCE, "r", encoding="utf-8") as stream:
        source = stream.read()
    assert EXPECTED_TOKEN not in source, "The ELF token must not be copied into the source."
    body = process_function_body(source)
    assert "std::string" in body, "process_line does not use std::string operations."
    assert not re.search(r"\bchar\s+\w+\s*\[", body), (
        "process_line still contains a fixed-size character buffer."
    )
    assert not re.search(r"\b(?:strcpy|strncpy|strcat|sprintf|vsprintf|gets)\s*\(", body), (
        "process_line still uses an unsafe C-string operation."
    )

    result = subprocess.run(
        ["g++", "-O2", "-std=c++11", SOURCE, "-o", "/tmp/verifier_processor"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, "Patched main.cpp does not compile:\n" + result.stderr.decode(errors="replace")


def test_patched_processor_behavior():
    assert os.path.isfile(BINARY), f"{BINARY} does not exist."
    assert os.access(BINARY, os.X_OK), f"{BINARY} is not executable."
    with open(BINARY, "rb") as stream:
        assert stream.read(4) == b"\x7fELF", f"{BINARY} is not an ELF executable."
    with open(BINARY, "rb") as submitted, open("/home/user/processor.elf", "rb") as original:
        assert submitted.read() != original.read(), "patched_processor is just the original vulnerable binary."

    ssn1 = f"{secrets.randbelow(900)+100:03d}-{secrets.randbelow(90)+10:02d}-{secrets.randbelow(9000)+1000:04d}"
    ssn2 = f"{secrets.randbelow(900)+100:03d}-{secrets.randbelow(90)+10:02d}-{secrets.randbelow(9000)+1000:04d}"
    card1 = "".join(str(secrets.randbelow(10)) for _ in range(16))
    card2 = "".join(str(secrets.randbelow(10)) for _ in range(16))
    lines = [
        "ordinary line that must remain unchanged",
        f"identities: {ssn1}, {ssn2}; cards: {card1} and {card2}",
        "LONG: " + ("safe-string-data-" * 30) + ssn1 + " / " + card2,
        "near misses: 12-345-6789 1234-56-7890 123456789012345 12345678901234567",
        "prefix123-45-6789suffix and prefix4111222233334444suffix",
    ]
    expected = "\n".join(redact(line) for line in lines) + "\n"
    assert run_processor(BINARY, lines) == expected, "patched_processor produced incorrect redaction or truncated data."
    assert run_processor("/tmp/verifier_processor", lines) == expected, "Patched main.cpp does not implement the required behavior."


def test_clean_log_exists():
    assert os.path.isfile(CLEAN_LOG), f"{CLEAN_LOG} does not exist."


def test_clean_log_redaction():
    assert os.path.isfile(CLEAN_LOG), f"{CLEAN_LOG} does not exist."
    with open(CLEAN_LOG, "r", encoding="utf-8", newline="") as stream:
        content = stream.read()

    assert "***-**-****" in content, "SSNs were not redacted properly in clean.log."
    assert "123-45-6789" not in content, "Unredacted SSN (123-45-6789) found in clean.log."
    assert "555-12-3456" not in content, "Unredacted SSN (555-12-3456) found in clean.log."
    assert "************4444" in content, "CC ending in 4444 was not redacted properly in clean.log."
    assert "4111222233334444" not in content, "Unredacted CC (4111222233334444) found in clean.log."
    assert "************7654" in content, "CC ending in 7654 was not redacted properly in clean.log."
    assert "9876543210987654" not in content, "Unredacted CC (9876543210987654) found in clean.log."

    with open(RAW_LOG, "r", encoding="utf-8", newline="") as stream:
        raw_lines = stream.read().splitlines()
    expected = "\n".join(redact(line) for line in raw_lines) + "\n"
    assert content == expected, "clean.log is not the exact output required for raw.log."
    assert run_processor(BINARY, raw_lines) == expected, "patched_processor does not reproduce clean.log from raw.log."


def test_clean_log_long_line():
    with open(CLEAN_LOG, "r", encoding="utf-8") as stream:
        content = stream.read()
    long_line = "LONG: This is a very long line that would normally cause a buffer overflow because it exceeds the one hundred and twenty eight character limit that was hardcoded into the extremely poorly written legacy cpp application that we are testing right now."
    assert long_line in content, "The long line was truncated or is missing in clean.log, indicating the buffer overflow was not properly fixed."


def test_sshd_config():
    config_path = "/home/user/sshd_config"
    assert os.path.isfile(config_path), f"{config_path} does not exist."
    with open(config_path, "r", encoding="utf-8") as stream:
        content = stream.read()

    lines = [line.strip() for line in content.splitlines() if line.strip() and not line.strip().startswith("#")]

    def check_directive(directive, expected_value):
        pattern = re.compile(rf"^{re.escape(directive)}[\s=]+{re.escape(expected_value)}$", re.IGNORECASE)
        return any(pattern.match(line) for line in lines)

    assert check_directive("Port", "2222"), "Port 2222 directive missing or incorrect in sshd_config."
    assert check_directive("PasswordAuthentication", "no"), "PasswordAuthentication no directive missing or incorrect in sshd_config."
    assert check_directive("X11Forwarding", "no"), "X11Forwarding no directive missing or incorrect in sshd_config."
    assert check_directive("PermitRootLogin", "no"), "PermitRootLogin no directive missing or incorrect in sshd_config."
    assert check_directive("AllowUsers", "user"), "AllowUsers user directive missing or incorrect in sshd_config."
    assert check_directive("MACs", "hmac-sha2-256"), "MACs hmac-sha2-256 directive missing or incorrect in sshd_config."

    parsed = []
    for line in lines:
        parts = re.split(r"[\s=]+", line, maxsplit=1)
        assert len(parts) == 2, f"Invalid or extra sshd_config line: {line}"
        parsed.append((parts[0].lower(), parts[1].strip().lower()))

    required = [
        ("port", "2222"),
        ("passwordauthentication", "no"),
        ("x11forwarding", "no"),
        ("permitrootlogin", "no"),
        ("allowusers", "user"),
        ("macs", "hmac-sha2-256"),
    ]
    allowed = required + [("hostkey", "/home/user/ssh_host_rsa_key")]
    counts = collections.Counter(parsed)
    for directive in required:
        assert counts[directive] == 1, f"sshd_config must contain exactly one {directive[0]} directive."
    assert counts[("hostkey", "/home/user/ssh_host_rsa_key")] <= 1, "Only the specified optional HostKey directive is allowed."
    assert all(item in allowed for item in parsed), "sshd_config contains directives other than the six required directives and optional HostKey."
    assert len(parsed) in (6, 7), "sshd_config contains duplicate or extra directives."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
