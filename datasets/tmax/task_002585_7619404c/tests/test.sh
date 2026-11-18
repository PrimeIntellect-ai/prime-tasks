#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import secrets
import subprocess
import tempfile


def run(command, timeout=10):
    return subprocess.run(command, capture_output=True, text=True, timeout=timeout)


def test_cracked_pin():
    path = "/home/user/cracked_pin.txt"
    assert os.path.isfile(path), f"File not found: {path}"
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "1234", f"Expected '1234', but got '{content}' in {path}"
    with open(path, "rb") as f:
        assert f.read() == b"1234", "cracked_pin.txt must contain only the four digits"


def test_exploit_generation():
    exploit_script = "/home/user/exploit.py"
    payload_file = "/home/user/malicious.cfg"

    assert os.path.isfile(exploit_script), f"Exploit script not found: {exploit_script}"
    if os.path.exists(payload_file):
        os.remove(payload_file)

    result = run(["python3", exploit_script])
    assert result.returncode == 0, f"Exploit script failed to run. Stderr: {result.stderr}"
    assert os.path.isfile(payload_file), f"Payload file was not generated at {payload_file}"


def test_exploit_execution():
    parser = "/home/user/legacy_parser"
    payload_file = "/home/user/malicious.cfg"

    assert os.path.isfile(parser), f"Legacy parser not found: {parser}"
    assert os.path.isfile(payload_file), f"Payload file not found: {payload_file}"

    result = run([parser, payload_file])
    assert "POLICY_VIOLATION_TRIGGERED" in result.stdout, "Exploit failed: output did not contain 'POLICY_VIOLATION_TRIGGERED'"
    assert result.returncode == 0, f"Legacy parser exited with {result.returncode}"
    assert result.stdout == "POLICY_VIOLATION_TRIGGERED\n", f"Legacy parser output was not exact: {result.stdout!r}"


def test_secure_parser_compiled_from_modified_source():
    source = "/home/user/legacy_parser.c"
    secure_parser = "/home/user/secure_parser"

    assert os.path.isfile(source), f"Modified source not found: {source}"
    assert not os.path.islink(source), f"Source must be a regular file, not a symlink: {source}"
    assert os.path.isfile(secure_parser), f"Secure parser not found: {secure_parser}"
    assert os.access(secure_parser, os.X_OK), f"Secure parser is not executable: {secure_parser}"
    with open(secure_parser, "rb") as f:
        assert f.read(4) == b"\x7fELF", "secure_parser must be a compiled ELF executable"

    with tempfile.TemporaryDirectory() as directory:
        rebuilt = os.path.join(directory, "secure_parser")
        result = run(["gcc", "-O0", "-o", rebuilt, source], timeout=30)
        assert result.returncode == 0, f"Modified source does not compile with the required command: {result.stderr}"
        with open(secure_parser, "rb") as f:
            submitted_bytes = f.read()
        with open(rebuilt, "rb") as f:
            rebuilt_bytes = f.read()
        assert submitted_bytes == rebuilt_bytes, "secure_parser was not produced from the submitted legacy_parser.c using gcc -O0"


def test_secure_parser_redaction():
    secure_parser = "/home/user/secure_parser"
    test_config = "/tmp/test_config.txt"

    with open(test_config, "w") as f:
        f.write("user_auth_token,PIN=9876,extra_data")

    result = run([secure_parser, test_config])
    expected_output = "Config loaded: user_auth_token,PIN=****,extra_data"
    assert expected_output in result.stdout, f"Redaction failed. Expected to find '{expected_output}' in stdout, but got: {result.stdout}"
    assert result.returncode == 0
    assert result.stdout == expected_output + "\n"


def test_secure_parser_general_redaction():
    secure_parser = "/home/user/secure_parser"

    cases = []
    for i in range(8):
        pin1 = f"{secrets.randbelow(10000):04d}"
        pin2 = f"{secrets.randbelow(10000):04d}"
        cases.append((
            f"n{i},PIN={pin1},x,PIN={pin2},z",
            f"n{i},PIN=****,x,PIN=****,z",
        ))
    cases.extend([
        ("PIN=0000", "PIN=****"),
        ("xPIN=9999,y", "xPIN=****,y"),
        ("PIN=12x4,PIN=abc1", "PIN=12x4,PIN=abc1"),
    ])

    for index, (input_text, expected_text) in enumerate(cases):
        path = f"/tmp/redaction_case_{index}.cfg"
        with open(path, "w") as f:
            f.write(input_text)
        result = run([secure_parser, path])
        assert result.returncode == 0, f"secure_parser failed for {input_text!r}: {result.stderr}"
        assert result.stdout == f"Config loaded: {expected_text}\n", (
            f"Incorrect redaction for {input_text!r}: {result.stdout!r}"
        )


def test_secure_parser_fixed_overflow():
    secure_parser = "/home/user/secure_parser"
    payload_file = "/home/user/malicious.cfg"

    assert os.path.isfile(payload_file), f"Payload file not found: {payload_file}"
    result = run([secure_parser, payload_file])
    assert "POLICY_VIOLATION_TRIGGERED" not in result.stdout, "Vulnerability not fixed: secure_parser still triggered policy violation with malicious payload"

    for index, length in enumerate((68, 257, 4096)):
        marker = chr(ord("A") + index)
        path = f"/tmp/overflow_case_{index}.cfg"
        with open(path, "w") as f:
            f.write(marker * length)
        result = run([secure_parser, path])
        assert result.returncode == 0, f"secure_parser crashed or failed on a {length}-byte token"
        assert "POLICY_VIOLATION_TRIGGERED" not in result.stdout
        assert result.stdout == f"Config loaded: {marker * 63}\n", (
            f"Input was not safely bounded to the 63-character buffer capacity: {result.stdout!r}"
        )


def test_secure_parser_hash():
    secure_parser = "/home/user/secure_parser"
    hash_file = "/home/user/secure_parser.sha256"
    assert os.path.isfile(hash_file), f"Hash file not found: {hash_file}"

    result = run(["sha256sum", "-c", hash_file])
    assert result.returncode == 0, f"Hash verification failed. Output: {result.stdout}\nStderr: {result.stderr}"

    with open(hash_file, "r") as f:
        checksum_line = f.read()
    match = re.fullmatch(r"([0-9a-f]{64}) ([ *])(/home/user/secure_parser)\n?", checksum_line)
    assert match, "Checksum must be one standard sha256sum line for /home/user/secure_parser"
    with open(secure_parser, "rb") as f:
        actual = hashlib.sha256(f.read()).hexdigest()
    assert match.group(1) == actual, "Recorded SHA-256 does not match secure_parser"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
