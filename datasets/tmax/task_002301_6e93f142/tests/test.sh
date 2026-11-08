#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import subprocess
import tempfile

import pytest

CSP = b"Content-Security-Policy: default-src 'self'\n"
SSN_RE = re.compile(rb"SSN: [0-9]{3}-[0-9]{2}-[0-9]{4}")


def secured(payload):
    return CSP + SSN_RE.sub(b"SSN: REDACTED!!!", payload)


def run_inspector(binary, payload):
    with tempfile.NamedTemporaryFile(prefix="traffic_", delete=False) as f:
        f.write(payload)
        input_path = f.name

    env = os.environ.copy()
    env["ASAN_OPTIONS"] = "detect_leaks=0:halt_on_error=1"
    try:
        attempts = ([binary, input_path], [binary])
        results = []
        for command in attempts:
            proc = subprocess.run(
                command,
                input=payload,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=5,
                env=env,
            )
            results.append(proc)
            if proc.returncode == 0:
                return proc.stdout

        details = b"\n--- fallback attempt ---\n".join(
            p.stderr + b"\nstdout:\n" + p.stdout for p in results
        ).decode("utf-8", errors="replace")
        pytest.fail(f"{binary} failed for both file and stdin input modes:\n{details}")
    finally:
        os.unlink(input_path)


def random_ssn():
    return f"{random.randrange(100, 1000):03d}-{random.randrange(10, 100):02d}-{random.randrange(1000, 10000):04d}".encode()


def behavioral_cases():
    first = random_ssn()
    second = random_ssn()
    return [
        b"HTTP/1.1 200 OK\n\nNo sensitive value here.\n",
        b"prefix SSN: " + first + b" suffix\n",
        (
            b"HTTP/1.1 200 OK\nX-Long: "
            + b"A" * 260
            + b"\nFirst SSN: "
            + first
            + b"\nSecond SSN: "
            + second
            + b"\nTail: "
            + b"Z" * 300
            + b"\n"
        ),
    ]


def assert_behavior(binary):
    for payload in behavioral_cases():
        actual = run_inspector(binary, payload)
        assert actual == secured(payload), (
            f"{binary} did not prepend the exact CSP header, preserve the payload, "
            "and redact every SSN correctly"
        )


def test_hidden_ca_txt():
    path = "/home/user/hidden_ca.txt"
    assert os.path.isfile(path), f"File {path} is missing. Did you analyze the legacy binary and extract the URL?"

    with open(path, 'r') as f:
        content = f.read().strip()

    expected_url = "https://staging-ca.internal.net/cert.pem"
    assert expected_url in content, f"File {path} does not contain the correct staging CA URL."


def test_fixed_inspector_compiled():
    path = "/home/user/fixed_inspector"
    assert os.path.isfile(path), f"File {path} is missing. Did you compile the fixed C code?"
    assert os.access(path, os.X_OK), f"File {path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File {path} is not a compiled ELF binary."


def test_safe_traffic_txt():
    path = "/home/user/safe_traffic.txt"
    assert os.path.isfile(path), f"File {path} is missing. Did you run the fixed binary and redirect output?"

    with open(path, 'r') as f:
        content = f.read()

    assert "Content-Security-Policy: default-src 'self'" in content, "The safe_traffic.txt file does not contain the prepended Content-Security-Policy header."
    assert "SSN: REDACTED!!!" in content, "The safe_traffic.txt file does not properly redact the SSN with 'REDACTED!!!'."
    assert "Status: Active" in content, "The safe_traffic.txt file is missing the 'Status: Active' line, which indicates the buffer overflow fix might have truncated the output."
    assert "SSN: 987-65-4321" not in content, "The original SSN is still present in the safe_traffic.txt file."

    with open("/home/user/raw_traffic.txt", "rb") as f:
        raw = f.read()
    expected = secured(raw)
    with open(path, "rb") as f:
        stored = f.read()
    actual = run_inspector("/home/user/fixed_inspector", raw)
    assert actual == expected, "fixed_inspector does not correctly process raw_traffic.txt."
    assert stored == actual, "safe_traffic.txt is not the output produced by fixed_inspector for raw_traffic.txt."


def test_fixed_inspector_general_behavior():
    assert_behavior("/home/user/fixed_inspector")


def test_cwe_120_fix_in_source():
    path = "/home/user/traffic_inspector.c"
    assert os.path.isfile(path), f"File {path} is missing."

    with open(path, 'r') as f:
        content = f.read()

    # Compile the submitted source independently with AddressSanitizer so the
    # source itself, rather than only the submitted executable, is exercised.
    rebuilt = "/tmp/rebuilt_inspector"
    proc = subprocess.run(
        [
            "gcc",
            "-std=c11",
            "-O1",
            "-g",
            "-fno-omit-frame-pointer",
            "-fsanitize=address",
            path,
            "-o",
            rebuilt,
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert proc.returncode == 0, "traffic_inspector.c does not compile with gcc:\n" + proc.stderr.decode("utf-8", errors="replace")
    assert_behavior(rebuilt)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
