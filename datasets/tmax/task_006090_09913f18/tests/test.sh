#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import subprocess


def assert_exact_log(path, expected):
    assert os.path.isfile(path), f"File {path} does not exist or is not a regular file."
    assert not os.path.islink(path), f"File {path} must not be a symbolic link."
    with open(path, "rb") as f:
        content = f.read()
    expected_bytes = expected.encode("ascii")
    assert content in (expected_bytes, expected_bytes + b"\n"), \
        f"Expected only {expected!r} with at most one trailing newline, but got {content!r}"


def test_permissions_log():
    binary = "/home/user/login_handler"
    assert os.path.isfile(binary), f"Binary {binary} does not exist or is not a regular file."
    expected = stat.filemode(os.stat(binary).st_mode)
    assert len(expected) == 10
    assert_exact_log("/home/user/permissions.log", expected)


def test_vulnerability_log():
    binary = "/home/user/login_handler"
    assert os.path.isfile(binary), f"Binary {binary} does not exist or is not a regular file."
    with open(binary, "rb") as f:
        data = f.read()
    assert data.startswith(b"\x7fELF"), f"{binary} is not an ELF binary."

    matches = re.findall(rb"https://malicious\.example\.com[^\x00\s]*", data)
    expected_bytes = b"https://malicious.example.com/redirect?url=http://trusted.com"
    assert matches == [expected_bytes], \
        f"Expected the supplied binary to contain exactly the known malicious URL; found {matches!r}"
    assert_exact_log("/home/user/vulnerability.log", matches[0].decode("ascii"))


def test_cert_status_log():
    cert_dir = "/home/user/certs"
    ca = os.path.join(cert_dir, "ca.crt")
    intermediate = os.path.join(cert_dir, "intermediate.crt")
    server = os.path.join(cert_dir, "server.crt")
    for path in (ca, intermediate, server):
        assert os.path.isfile(path), f"Certificate {path} does not exist or is not a regular file."

    result = subprocess.run(
        ["openssl", "verify", "-CAfile", ca, "-untrusted", intermediate, server],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    expected = "VALID" if result.returncode == 0 else "INVALID"
    assert expected == "VALID", \
        f"The supplied certificate chain did not validate: {result.stdout}{result.stderr}"
    assert_exact_log("/home/user/cert_status.log", expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
