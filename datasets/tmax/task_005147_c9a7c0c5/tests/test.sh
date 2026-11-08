#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import stat
import subprocess
import tempfile
import pytest

SCRIPT_PATH = "/home/user/classifier.sh"


def run_classifier(request_path):
    return subprocess.run([SCRIPT_PATH, request_path], capture_output=True, timeout=10).returncode


def test_classifier_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Classifier script not found at {SCRIPT_PATH}."

    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Classifier script at {SCRIPT_PATH} is not executable."


def test_adversarial_corpus():
    clean_dir = "/app/corpus/clean/"
    assert os.path.isdir(clean_dir), f"Clean corpus directory missing: {clean_dir}"

    clean_files = [
        os.path.join(clean_dir, f)
        for f in os.listdir(clean_dir)
        if os.path.isfile(os.path.join(clean_dir, f))
    ]
    assert clean_files, "Clean corpus is empty."

    failed_clean = []
    for cf in clean_files:
        if run_classifier(cf) != 0:
            failed_clean.append(os.path.basename(cf))

    if failed_clean:
        pytest.fail(
            f"{len(failed_clean)} of {len(clean_files)} clean requests rejected: "
            + ", ".join(failed_clean)
        )

    malicious_user_agent = "EvilBot/v3.4.1"
    restricted_path = "/system/backup.tar.gz"
    cases = []

    for _ in range(50):
        cases.append((0, "GET /index.html HTTP/1.1\r\nHost: example.com\r\nUser-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64)\r\nAccept: */*\r\n"))
    for _ in range(25):
        cases.append((1, f"GET /index.html HTTP/1.1\r\nHost: example.com\r\nUser-Agent: {malicious_user_agent}\r\nAccept: */*\r\n"))
    for _ in range(25):
        cases.append((1, f"GET {restricted_path} HTTP/1.1\r\nHost: example.com\r\nUser-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64)\r\nAccept: */*\r\n"))

    random.SystemRandom().shuffle(cases)
    failures = []
    with tempfile.TemporaryDirectory(prefix="waf-requests-") as request_dir:
        generated = []
        for expected, request in cases:
            name = secrets.token_hex(16)
            path = os.path.join(request_dir, name)
            padding = secrets.token_hex(random.SystemRandom().randint(0, 48))
            with open(path, "w", encoding="utf-8", newline="") as f:
                f.write(request)
                f.write(f"X-Padding: {padding}\r\n\r\n")
            generated.append((path, expected))

        random.SystemRandom().shuffle(generated)
        for path, expected in generated:
            actual = run_classifier(path)
            if actual != expected:
                failures.append((os.path.basename(path), expected, actual))

    if failures:
        pytest.fail(
            f"{len(failures)} dynamically generated requests were misclassified: "
            + ", ".join(f"{name} expected {expected}, got {actual}" for name, expected, actual in failures[:10])
        )


def test_network_interface_waf0():
    try:
        result = subprocess.run(["ip", "addr", "show", "waf0"], capture_output=True, text=True, check=True)
        output = result.stdout
        assert "10.100.0.1/24" in output or "10.100.0.1" in output, "waf0 interface exists but does not have the expected IP address 10.100.0.1/24."
    except subprocess.CalledProcessError:
        pytest.fail("Network interface 'waf0' does not exist or 'ip' command failed.")


def test_tls_certificates():
    crt_path = "/home/user/certs/tls.crt"
    key_path = "/home/user/certs/tls.key"

    assert os.path.isfile(crt_path), f"TLS certificate missing at {crt_path}."
    assert os.path.isfile(key_path), f"TLS private key missing at {key_path}."

    crt_check = subprocess.run(["openssl", "x509", "-in", crt_path, "-noout"], capture_output=True)
    assert crt_check.returncode == 0, f"File at {crt_path} is not a valid x509 certificate."

    key_check = subprocess.run(["openssl", "pkey", "-in", key_path, "-noout"], capture_output=True)
    assert key_check.returncode == 0, f"File at {key_path} is not a valid private key."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
