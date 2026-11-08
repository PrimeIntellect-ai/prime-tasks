#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import os
import re
import secrets
import shutil
import string
import subprocess
import tempfile
import zipfile

HANDLER = "/home/user/upload_handler.sh"
KEYS = "/home/user/.ssh/authorized_keys"
CAPTURE = "/home/user/network_capture.log"
CRACK_SCRIPT = "/home/user/crack.sh"
PAYLOAD_ZIP = "/home/user/extracted_payload.zip"
MALWARE = "/home/user/malware.sh"
HASH_FILE = "/home/user/malware_hash.txt"
EXPECTED_HASH_FILE = "/tests/expected_hash.txt"


def expected_hash():
    assert os.path.isfile(EXPECTED_HASH_FILE), "Trusted expected hash is missing from the test bundle."
    with open(EXPECTED_HASH_FILE, "r", encoding="ascii") as f:
        value = f.read().strip()
    assert re.fullmatch(r"[0-9a-f]{64}", value), "Trusted expected hash is malformed."
    return value


def payload_from_capture():
    assert os.path.isfile(CAPTURE), f"File {CAPTURE} is missing."
    with open(CAPTURE, "r", encoding="utf-8") as f:
        capture = f.read()
    match = re.search(
        r"X-Filename: payload\.zip\.b64\r?\n\r?\n([A-Za-z0-9+/=]+)",
        capture,
    )
    assert match, "Could not locate the base64 ZIP payload in network_capture.log."
    return base64.b64decode(match.group(1), validate=True)


def read_malware_from_zip(path):
    with zipfile.ZipFile(path, "r") as archive:
        names = [name for name in archive.namelist() if os.path.basename(name.rstrip("/")) == "malware.sh"]
        assert len(names) == 1, "The ZIP must contain exactly one malware.sh entry."
        return archive.read(names[0], pwd=b"fox")


def test_upload_handler_patched():
    assert os.path.isfile(HANDLER), f"File {HANDLER} is missing."

    malicious_target = "/home/user/test_upload.txt"
    safe_target = "/home/user/uploads/test_upload.txt"
    for path in (malicious_target, safe_target):
        if os.path.exists(path):
            os.remove(path)

    env = os.environ.copy()
    env["FILENAME"] = "../../../home/user/test_upload.txt"
    process = subprocess.run(
        [HANDLER],
        input=b"test_content",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
        timeout=15,
    )
    assert process.returncode == 0, "The upload handler failed when given a traversal filename."
    assert not os.path.exists(malicious_target), (
        f"Path traversal vulnerability still exists! File was written to {malicious_target}"
    )
    assert os.path.exists(safe_target), (
        f"The script failed to write the file to the safe directory {safe_target}"
    )
    with open(safe_target, "rb") as f:
        assert f.read() == b"test_content", "The uploaded file content does not match the input."


def test_ssh_keys_remediated():
    assert os.path.isfile(KEYS), f"File {KEYS} is missing."
    with open(KEYS, "r", encoding="utf-8") as f:
        content = f.read()
    assert "LegitimateKey123" in content, "The legitimate SSH key was removed from authorized_keys."
    assert "attacker@evil.corp" not in content, "The attacker's SSH key is still present in authorized_keys."


def test_extracted_payload_zip_is_authentic_and_valid():
    assert os.path.isfile(PAYLOAD_ZIP), f"File {PAYLOAD_ZIP} is missing."
    with open(PAYLOAD_ZIP, "rb") as f:
        submitted = f.read()
    assert submitted[:4] == b"PK\x03\x04", f"File {PAYLOAD_ZIP} does not appear to be a valid ZIP archive."
    assert submitted == payload_from_capture(), "The extracted ZIP does not match the payload in network_capture.log."

    malware_data = read_malware_from_zip(PAYLOAD_ZIP)
    assert hashlib.sha256(malware_data).hexdigest() == expected_hash(), (
        "The protected ZIP does not contain the expected malware payload."
    )


def test_crack_script_actually_bruteforces_and_extracts():
    assert os.path.isfile(CRACK_SCRIPT), f"File {CRACK_SCRIPT} is missing. You need to write the brute-force script."
    syntax = subprocess.run(["bash", "-n", CRACK_SCRIPT], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert syntax.returncode == 0, "crack.sh is not valid Bash syntax."

    original_zip = open(PAYLOAD_ZIP, "rb").read()
    original_malware = read_malware_from_zip(PAYLOAD_ZIP)
    letters = string.ascii_lowercase
    password = letters[secrets.randbelow(6)] + letters[secrets.randbelow(26)] + letters[secrets.randbelow(26)]

    with tempfile.TemporaryDirectory() as tmp:
        member_dir = os.path.join(tmp, "home", "user")
        os.makedirs(member_dir)
        member_path = os.path.join(member_dir, "malware.sh")
        with open(member_path, "wb") as f:
            f.write(original_malware)
        challenge = os.path.join(tmp, "challenge.zip")
        made = subprocess.run(
            ["zip", "-P", password, "-q", challenge, "home/user/malware.sh"],
            cwd=tmp,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        assert made.returncode == 0, "Test environment could not create the password challenge ZIP."
        shutil.copyfile(challenge, PAYLOAD_ZIP)
        challenge_bytes = open(challenge, "rb").read()

        try:
            if os.path.exists(MALWARE):
                os.remove(MALWARE)
            result = subprocess.run(
                ["bash", CRACK_SCRIPT],
                cwd="/home/user",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=180,
            )
            assert result.returncode == 0, "crack.sh failed to brute-force a three-letter lowercase password."
            assert open(PAYLOAD_ZIP, "rb").read() == challenge_bytes, (
                "crack.sh replaced the challenge archive instead of cracking it."
            )
            assert os.path.isfile(MALWARE), "crack.sh did not extract malware.sh to /home/user/malware.sh."
            with open(MALWARE, "rb") as f:
                assert f.read() == original_malware, "crack.sh extracted incorrect malware content."
        finally:
            with open(PAYLOAD_ZIP, "wb") as f:
                f.write(original_zip)


def test_malware_and_hash_correct():
    assert os.path.isfile(MALWARE), f"File {MALWARE} is missing."
    with open(MALWARE, "rb") as f:
        actual_malware_hash = hashlib.sha256(f.read()).hexdigest()
    assert actual_malware_hash == expected_hash(), "The extracted malware.sh is not the expected payload."

    assert os.path.isfile(HASH_FILE), f"File {HASH_FILE} is missing."
    with open(HASH_FILE, "r", encoding="ascii") as f:
        raw_hash = f.read()
    assert re.fullmatch(r"[0-9a-f]{64}\n?", raw_hash), (
        "malware_hash.txt must contain only one 64-character lowercase hexadecimal hash."
    )
    assert raw_hash.strip() == expected_hash(), (
        f"The hash in {HASH_FILE} does not match the expected hash of the malware."
    )
    assert raw_hash.strip() == actual_malware_hash, (
        "malware_hash.txt does not contain the SHA-256 hash of /home/user/malware.sh."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
