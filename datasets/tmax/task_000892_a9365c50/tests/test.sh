#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import subprocess
import tempfile
import textwrap
import uuid
import pytest

GREETER_SOURCE = r'''#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void admin_shell() {
    printf("POLICY_BYPASS_SUCCESS\n");
    exit(0);
}

void greet() {
    char buffer[32];
    printf("Enter your username for the SSH banner: ");
    gets(buffer);
    printf("Hello, %s\n", buffer);
}

int main() {
    greet();
    return 0;
}
'''


def build_expected_greeter(tmpdir):
    source = os.path.join(tmpdir, "greeter.c")
    binary = os.path.join(tmpdir, "greeter")
    with open(source, "w") as f:
        f.write(GREETER_SOURCE)
    subprocess.run(
        ["gcc", "-fno-stack-protector", "-no-pie", "-O0", "-o", binary, source],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    with open(binary, "rb") as f:
        return hashlib.sha256(f.read()).digest()


def file_digest(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).digest()


def test_cwe_identification():
    cwe_file = "/home/user/cwe.txt"
    assert os.path.isfile(cwe_file), f"File {cwe_file} does not exist."

    with open(cwe_file, "r") as f:
        content = f.read().strip().upper()

    valid_cwes = ["CWE-120", "CWE-121", "CWE-119", "CWE-242"]
    found = any(cwe in content for cwe in valid_cwes)
    assert found, f"File {cwe_file} does not contain a valid CWE identifier for the vulnerability. Expected one of {valid_cwes}."
    assert content == "CWE-121", "cwe.txt must contain only the precise primary identifier CWE-121."


def test_exploit_crafting():
    exploit_script = "/home/user/exploit.py"
    target_binary = "/home/user/greeter"

    assert os.path.isfile(exploit_script), f"Exploit script {exploit_script} does not exist."
    assert os.path.isfile(target_binary), f"Target binary {target_binary} does not exist."

    with tempfile.TemporaryDirectory() as tmpdir:
        expected_digest = build_expected_greeter(tmpdir)
        assert file_digest(target_binary) == expected_digest, \
            "The supplied greeter ELF was modified or replaced."
        assert os.access(target_binary, os.X_OK), "The supplied greeter is not executable."

        try:
            # Start the verified ELF before executing any agent-controlled Python,
            # preventing exploit.py from swapping the path before exec.
            p2 = subprocess.Popen(
                [target_binary], stdin=subprocess.PIPE,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE
            )
            p1 = subprocess.Popen(
                ["python3", exploit_script],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE
            )
            payload, exploit_stderr = p1.communicate(timeout=5)
            assert p1.returncode == 0, \
                f"Exploit script exited with {p1.returncode}: {exploit_stderr.decode(errors='ignore')}"
            stdout, stderr = p2.communicate(input=payload, timeout=5)

            output = stdout.decode(errors='ignore')
            assert "POLICY_BYPASS_SUCCESS" in output, \
                "The exploit did not successfully hijack execution to print POLICY_BYPASS_SUCCESS."
            assert file_digest(target_binary) == expected_digest, \
                "The supplied greeter ELF was modified or replaced during the exploit."
        except subprocess.TimeoutExpired:
            p1.kill() if 'p1' in locals() and p1.poll() is None else None
            p2.kill() if 'p2' in locals() and p2.poll() is None else None
            pytest.fail("The exploit execution timed out.")
        except Exception as e:
            pytest.fail(f"An error occurred while running the exploit: {e}")


def test_sshd_config_fixed():
    fixed_config = "/home/user/sshd_config.fixed"
    assert os.path.isfile(fixed_config), f"Hardened config file {fixed_config} does not exist."

    with open(fixed_config, "r") as f:
        lines = f.readlines()

    def check_directive(directive, expected_value):
        pattern = re.compile(rf"^\s*{directive}\s+{expected_value}\s*$", re.IGNORECASE)
        for line in lines:
            if pattern.match(line):
                return True
        return False

    assert check_directive("PermitRootLogin", "no"), "PermitRootLogin is not explicitly set to 'no' or is commented out."
    assert check_directive("PasswordAuthentication", "no"), "PasswordAuthentication is not explicitly set to 'no' or is commented out."
    assert check_directive("Protocol", "2"), "Protocol is not explicitly set to '2' or is commented out."


def test_policy_as_code_bad_config():
    policy_script = "/home/user/policy.py"
    bad_config = "/home/user/sshd_config"

    assert os.path.isfile(policy_script), f"Policy script {policy_script} does not exist."
    assert os.path.isfile(bad_config), f"Config file {bad_config} does not exist."

    result = subprocess.run(["python3", policy_script, bad_config], capture_output=True, text=True)

    assert result.returncode == 1, f"Policy script should exit with code 1 for insecure config, but exited with {result.returncode}."
    assert "FAIL" in result.stdout, "Policy script should print FAIL to stdout for insecure config."


def test_policy_as_code_good_config():
    policy_script = "/home/user/policy.py"
    good_config = "/home/user/sshd_config.fixed"

    assert os.path.isfile(policy_script), f"Policy script {policy_script} does not exist."
    assert os.path.isfile(good_config), f"Config file {good_config} does not exist."

    result = subprocess.run(["python3", policy_script, good_config], capture_output=True, text=True)

    assert result.returncode == 0, f"Policy script should exit with code 0 for hardened config, but exited with {result.returncode}."
    assert "PASS" in result.stdout, "Policy script should print PASS to stdout for hardened config."


def test_policy_as_code_dynamic_configs():
    policy_script = "/home/user/policy.py"
    assert os.path.isfile(policy_script), f"Policy script {policy_script} does not exist."

    cases = [
        ("Port 2222\nProtocol 2\nPasswordAuthentication no\nPermitRootLogin no\n", 0, "PASS"),
        ("# arbitrary config\n  PermitRootLogin no\nPasswordAuthentication no\n  Protocol 2\n", 0, "PASS"),
        ("PasswordAuthentication no\nProtocol 2\n", 1, "FAIL"),
        ("#PermitRootLogin no\nPasswordAuthentication no\nProtocol 2\n", 1, "FAIL"),
        ("PermitRootLogin yes\nPasswordAuthentication no\nProtocol 2\n", 1, "FAIL"),
        ("PermitRootLogin no\n# PasswordAuthentication no\nProtocol 2\n", 1, "FAIL"),
        ("PermitRootLogin no\nPasswordAuthentication yes\nProtocol 2\n", 1, "FAIL"),
        ("PermitRootLogin no\nPasswordAuthentication no\n#Protocol 2\n", 1, "FAIL"),
        ("PermitRootLogin no\nPasswordAuthentication no\nProtocol 1\n", 1, "FAIL"),
    ]

    with tempfile.TemporaryDirectory(prefix="policy-cases-") as tmpdir:
        for index, (content, expected_code, expected_output) in enumerate(cases):
            path = os.path.join(tmpdir, f"{uuid.uuid4().hex}-{index}.conf")
            with open(path, "w") as f:
                f.write(content)
            result = subprocess.run(
                ["python3", policy_script, path], capture_output=True, text=True, timeout=5
            )
            assert result.returncode == expected_code, \
                f"Unexpected exit code for dynamically generated config {index}."
            assert result.stdout.strip() == expected_output, \
                f"Expected exactly {expected_output} for dynamically generated config {index}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
