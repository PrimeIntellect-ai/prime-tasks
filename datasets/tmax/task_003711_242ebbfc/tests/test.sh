#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import stat
import string
import subprocess

EXPECTED_SOURCE = b'''#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 2) {
        return 2;
    }
    char *token = argv[1];
    if (strlen(token) < 5) {
        return 1;
    }
    int sum = 0;
    for(int i=0; i<4; i++) {
        sum += token[i];
    }
    char expected = (sum % 26) + 'A';

    if (token[4] == expected) {
        return 0; // Valid
    } else {
        return 1; // Invalid
    }
}
'''

EXPECTED_LOG = b'''[2023-10-01 10:00:01] IP: 10.0.0.5 - Token: TESTI123
[2023-10-01 10:05:22] IP: 192.168.1.100 - Token: ROOTX999
[2023-10-01 10:10:05] IP: 10.0.0.6 - Token: HACKTABC
[2023-10-01 10:12:30] IP: 172.16.5.5 - Token: TESTAXYZ
[2023-10-01 10:15:00] IP: 192.168.1.100 - Token: ROOTM444
[2023-10-01 10:20:11] IP: 10.0.0.99 - Token: FAKEQ000
'''


def is_valid_token(token: str) -> bool:
    """Python implementation of the C validation logic."""
    if len(token) < 5:
        return False
    sum_val = sum(ord(c) for c in token[:4])
    expected = chr((sum_val % 26) + ord('A'))
    return token[4] == expected


def get_expected_blocked_ips() -> list:
    """Parse the required log file and determine which IPs should be blocked."""
    log_path = "/home/user/server.log"
    assert os.path.isfile(log_path), f"Required input log is missing: {log_path}."

    blocked_ips = set()
    with open(log_path, "r") as f:
        for line in f:
            match = re.search(r"IP:\s+([^\s]+)\s+-\s+Token:\s+([^\s]+)", line)
            if match:
                ip = match.group(1)
                token = match.group(2)
                if not is_valid_token(token):
                    blocked_ips.add(ip)

    def ip_key(ip_str):
        try:
            return [int(part) for part in ip_str.split('.')]
        except ValueError:
            return [0]

    return sorted(list(blocked_ips), key=ip_key)


def run_program(path, args):
    try:
        return subprocess.run(
            [path] + args,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=2,
            check=False,
        )
    except subprocess.TimeoutExpired:
        raise AssertionError(f"{path} did not terminate for arguments {args!r}")


def test_provided_inputs_are_present_and_unchanged():
    source_path = "/home/user/validate.c"
    log_path = "/home/user/server.log"
    assert os.path.isfile(source_path), f"Required source file is missing: {source_path}."
    assert os.path.isfile(log_path), f"Required input log is missing: {log_path}."
    with open(source_path, "rb") as f:
        assert f.read() == EXPECTED_SOURCE, "The provided validate.c source was altered."
    with open(log_path, "rb") as f:
        assert f.read() == EXPECTED_LOG, "The provided server.log was altered."


def test_validate_executable_exists_and_runnable():
    """Test that validate.c was compiled into a real executable named validate."""
    executable_path = "/home/user/validate"
    assert os.path.isfile(executable_path), f"Compiled executable not found at {executable_path}."
    assert os.access(executable_path, os.X_OK), f"The file at {executable_path} is not executable."
    mode = os.stat(executable_path).st_mode
    assert stat.S_ISREG(mode), f"The file at {executable_path} is not a regular file."
    with open(executable_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "validate is not a compiled ELF executable."

    reference_path = "/tmp/reference_validate"
    built = subprocess.run(
        ["/usr/bin/gcc", "/home/user/validate.c", "-o", reference_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
        check=False,
    )
    assert built.returncode == 0, f"validate.c did not compile: {built.stderr.decode(errors='replace')}"

    argument_sets = [[], ["one", "two"]]
    tokens = ["", "A", "ABCD", "ABCDE", "TESTI123", "ROOTX999", "HACKTABC",
              "TESTAXYZ", "ROOTM444", "FAKEQ000", "AAAAA", "AAAAZ", "zzzzA"]
    alphabet = string.ascii_letters + string.digits
    for _ in range(128):
        length = secrets.randbelow(32) + 1
        tokens.append(''.join(secrets.choice(alphabet) for _ in range(length)))
    argument_sets.extend([[token] for token in tokens])

    for args in argument_sets:
        expected = run_program(reference_path, args)
        actual = run_program(executable_path, args)
        assert actual.returncode == expected.returncode, (
            f"validate returned {actual.returncode} for arguments {args!r}; "
            f"the compiled validate.c returns {expected.returncode}."
        )


def test_blocked_ips_report():
    """Test that blocked_ips.txt contains exactly the correct IPs in order."""
    report_path = "/home/user/blocked_ips.txt"
    assert os.path.isfile(report_path), f"Audit report file not found at {report_path}."

    expected_ips = get_expected_blocked_ips()

    with open(report_path, "r") as f:
        report_text = f.read()
    actual_ips = [line.strip() for line in report_text.splitlines() if line.strip()]

    assert actual_ips == expected_ips, (
        f"The contents of {report_path} are incorrect.\n"
        f"Expected: {expected_ips}\n"
        f"Found:    {actual_ips}"
    )
    assert report_text.splitlines() == expected_ips, (
        "The report must contain only one unmodified IP address per line, with no blank lines."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
