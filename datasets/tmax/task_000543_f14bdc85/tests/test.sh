#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pwd
import re
import secrets
import subprocess

ENFORCE = "/home/user/enforce.sh"
ENCRYPT = "/home/user/encrypt.py"
RAW = "/home/user/raw.log"
ENCRYPTED = "/home/user/encrypted.log"
DIFF = "/home/user/diff_analysis.txt"
PROBE_LOG = "/tmp/encrypt_probe.jsonl"


def test_enforce_sh_exists_and_executable():
    assert os.path.isfile(ENFORCE), f"{ENFORCE} does not exist."
    assert os.access(ENFORCE, os.X_OK), f"{ENFORCE} is not executable."


def test_encrypted_log_content():
    assert os.path.isfile(ENCRYPTED), f"{ENCRYPTED} does not exist."
    with open(ENCRYPTED, "r") as f:
        content = f.read().strip()

    expected_hex = "104c4d4d46475a404b50424b5540415d404b5f4741405a3026362325372132365a435a4e404b464a475a4043422e0a25424a4f46475a4b4d454b415d404b5f4741405a3026362325372132365a444d505a415a465a43464f4b4c2e0a"
    assert content == expected_hex, f"Content of {ENCRYPTED} is incorrect. Expected {expected_hex}, got {content}"


def test_diff_analysis_content():
    assert os.path.isfile(DIFF), f"{DIFF} does not exist."
    with open(DIFF, "r") as f:
        content = f.read().strip()

    expected_diff = "00000000000003"
    assert content == expected_diff, f"Content of {DIFF} is incorrect. Expected {expected_diff}, got {content}"


def test_script_executes_full_policy_on_fresh_inputs():
    with open(ENFORCE, "r", errors="replace") as f:
        source = f.read()
    assert re.search(r"\benv\s+(?:-i|--ignore-environment)\b", source), "enforce.sh must use env -i"
    assert re.search(r"\bunshare\s+(?:[^\n;]*\s)?(?:-n|--net)(?:\s|$)", source), "enforce.sh must use unshare -n"

    token = secrets.token_hex(12)
    raw_text = (
        f"{token} accepted from 172.19.23.41.\n"
        f"peer 8.8.4.4 then contacted 203.0.113.77 for {token}.\n"
    )
    redacted = (
        f"{token} accepted from [REDACTED].\n"
        f"peer [REDACTED] then contacted [REDACTED] for {token}.\n"
    )
    key = secrets.token_bytes(19)
    parent_netns = os.readlink("/proc/self/ns/net")

    probe = f'''#!/usr/bin/env python3
import json
import os
import sys

key = bytes.fromhex({key.hex()!r})
data = sys.stdin.buffer.read()
record = {{
    "stdin_hex": data.hex(),
    "environment": dict(os.environ),
    "netns": os.readlink("/proc/self/ns/net"),
}}
with open({PROBE_LOG!r}, "a") as log:
    log.write(json.dumps(record, sort_keys=True) + "\\n")
out = bytes(value ^ key[index % len(key)] for index, value in enumerate(data))
sys.stdout.write(out.hex())
'''

    with open(RAW, "w") as f:
        f.write(raw_text)
    with open(ENCRYPT, "w") as f:
        f.write(probe)
    os.chmod(ENCRYPT, 0o755)
    try:
        os.remove(PROBE_LOG)
    except FileNotFoundError:
        pass

    env = dict(os.environ)
    env["VERIFIER_ENV_CANARY"] = secrets.token_hex(16)
    completed = subprocess.run(
        [ENFORCE],
        cwd="/home/user",
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert completed.returncode == 0, f"enforce.sh failed when executed: {completed.stderr}"

    assert os.path.isfile(ENCRYPTED), f"{ENCRYPTED} was not generated"
    assert os.path.isfile(DIFF), f"{DIFF} was not generated"

    def encrypt(data):
        return bytes(value ^ key[index % len(key)] for index, value in enumerate(data))

    expected_encrypted = encrypt(redacted.encode()).hex()
    with open(ENCRYPTED, "r") as f:
        actual_encrypted = f.read().strip()
    assert actual_encrypted == expected_encrypted, "encrypted.log was not produced by redacting and encrypting the fresh raw.log"

    cipher_a = encrypt(b"BLOCK_A")
    cipher_b = encrypt(b"BLOCK_B")
    expected_diff = bytes(a ^ b for a, b in zip(cipher_a, cipher_b)).hex()
    with open(DIFF, "r") as f:
        actual_diff = f.read().strip()
    assert actual_diff == expected_diff, "diff_analysis.txt is not the XOR of the two fresh ciphertexts"
    assert re.fullmatch(r"[0-9a-f]+", actual_diff), "diff output must be continuous lowercase hexadecimal"

    assert os.path.isfile(PROBE_LOG), "the encryption utility was never executed"
    with open(PROBE_LOG, "r") as f:
        records = [json.loads(line) for line in f if line.strip()]

    expected_inputs = sorted([redacted.encode().hex(), b"BLOCK_A".hex(), b"BLOCK_B".hex()])
    actual_inputs = sorted(record["stdin_hex"] for record in records)
    assert actual_inputs == expected_inputs, "encrypt.py must be invoked exactly for the redacted log, BLOCK_A, and BLOCK_B"

    for record in records:
        assert "VERIFIER_ENV_CANARY" not in record["environment"], "encrypt.py inherited the caller environment; env -i was not effective"
        assert record["netns"] != parent_netns, "encrypt.py ran in the verifier's network namespace; unshare -n was not effective"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
