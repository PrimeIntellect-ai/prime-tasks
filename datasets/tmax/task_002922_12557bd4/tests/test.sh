#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import stat
import subprocess
import tempfile
import pytest

KEY_PATH = "/home/user/decrypted_id_rsa"
SANITIZER_PATH = "/home/user/sanitizer"
SOURCE_PATH = "/home/user/sanitizer.cpp"


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, timeout=kwargs.pop("timeout", 10), **kwargs)


def test_decrypted_id_rsa_exists_and_permissions():
    assert os.path.isfile(KEY_PATH), f"Decrypted SSH key not found at {KEY_PATH}"
    permissions = stat.S_IMODE(os.stat(KEY_PATH).st_mode)
    assert permissions == 0o600, f"Expected permissions 0600 for {KEY_PATH}, but got {oct(permissions)}"


def test_decrypted_id_rsa_is_valid():
    with open(KEY_PATH, "r", errors="replace") as f:
        content = f.read()

    assert "BEGIN RSA PRIVATE KEY" in content or "BEGIN OPENSSH PRIVATE KEY" in content, \
        f"File {KEY_PATH} does not appear to be a valid private key."
    assert "ENCRYPTED" not in content, f"File {KEY_PATH} appears to still be encrypted."

    derived = run(["ssh-keygen", "-y", "-P", "", "-f", KEY_PATH])
    assert derived.returncode == 0, \
        f"ssh-keygen could not parse the submitted key as an unencrypted private key: {derived.stderr.decode(errors='replace')}"

    public_path = "/app/compromised_id_rsa.pub"
    assert os.path.isfile(public_path), f"Expected public key missing at {public_path}"
    with open(public_path, "rb") as f:
        expected_parts = f.read().strip().split()
    actual_parts = derived.stdout.strip().split()
    assert len(expected_parts) >= 2 and len(actual_parts) >= 2
    assert actual_parts[:2] == expected_parts[:2], \
        "The decrypted private key does not correspond to /app/compromised_id_rsa"


def test_sanitizer_binary_exists():
    assert os.path.isfile(SANITIZER_PATH), f"Sanitizer binary not found at {SANITIZER_PATH}"
    assert os.access(SANITIZER_PATH, os.X_OK), f"Sanitizer binary at {SANITIZER_PATH} is not executable"
    with open(SANITIZER_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The sanitizer executable is not an ELF binary"


def test_sanitizer_source_exists():
    assert os.path.isfile(SOURCE_PATH), f"Sanitizer source not found at {SOURCE_PATH}"
    assert os.path.getsize(SOURCE_PATH) > 0, f"Sanitizer source at {SOURCE_PATH} is empty"


@pytest.fixture(scope="session")
def sanitizer_bins():
    assert os.path.isfile(SOURCE_PATH), f"Sanitizer source not found at {SOURCE_PATH}"
    rebuilt = os.path.join(tempfile.mkdtemp(prefix="sanitizer-build-"), "sanitizer")
    compiled = run(["g++", "-std=c++17", "-O2", SOURCE_PATH, "-o", rebuilt], timeout=30)
    assert compiled.returncode == 0, \
        f"sanitizer.cpp did not compile: {compiled.stderr.decode(errors='replace')}"
    assert os.path.isfile(rebuilt) and os.access(rebuilt, os.X_OK)
    return [SANITIZER_PATH, rebuilt]


def invoke(binary, payload):
    if isinstance(payload, str):
        payload = payload.encode()
    try:
        return subprocess.run([binary], input=payload, capture_output=True, timeout=2).returncode
    except subprocess.TimeoutExpired:
        pytest.fail(f"{binary} timed out on a test payload")


def test_sanitizer_adversarial_corpus():
    evil_dir = "/app/corpora/evil"
    clean_dir = "/app/corpora/clean"

    assert os.path.isdir(evil_dir), f"Evil corpus directory missing at {evil_dir}"
    assert os.path.isdir(clean_dir), f"Clean corpus directory missing at {clean_dir}"

    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir)
                  if os.path.isfile(os.path.join(evil_dir, f))]
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir)
                   if os.path.isfile(os.path.join(clean_dir, f))]

    assert len(evil_files) > 0, "No files found in evil corpus"
    assert len(clean_files) > 0, "No files found in clean corpus"

    bypassed_evil = []
    for evil_file in evil_files:
        with open(evil_file, "rb") as f:
            result = subprocess.run([SANITIZER_PATH], stdin=f, capture_output=True, timeout=2)
            if result.returncode != 1:
                bypassed_evil.append(os.path.basename(evil_file))

    modified_clean = []
    for clean_file in clean_files:
        with open(clean_file, "rb") as f:
            result = subprocess.run([SANITIZER_PATH], stdin=f, capture_output=True, timeout=2)
            if result.returncode != 0:
                modified_clean.append(os.path.basename(clean_file))

    error_msgs = []
    if bypassed_evil:
        error_msgs.append(f"{len(bypassed_evil)} of {len(evil_files)} evil bypassed: {', '.join(bypassed_evil[:5])}{'...' if len(bypassed_evil) > 5 else ''}")
    if modified_clean:
        error_msgs.append(f"{len(modified_clean)} of {len(clean_files)} clean modified/rejected: {', '.join(modified_clean[:5])}{'...' if len(modified_clean) > 5 else ''}")
    assert not bypassed_evil and not modified_clean, " | ".join(error_msgs)


def encoded_payload(obj, rng):
    items = list(obj.items())
    rng.shuffle(items)
    obj = dict(items)
    style = rng.randrange(3)
    if style == 0:
        return json.dumps(obj, separators=(",", ":"))
    if style == 1:
        return json.dumps(obj, indent=2)
    return " \n\t" + json.dumps(obj, ensure_ascii=True, separators=(", ", ": ")) + "\n"


def test_generated_hidden_adversarial_suite(sanitizer_bins):
    rng = random.SystemRandom()
    nonce = secrets.token_hex(12)

    safe_commands = [
        "uptime", "date", "whoami", "echo hello", "printf status",
        "uname -a", "pwd", "id", "hostname", "echo " + nonce
    ]
    safe_profiles = [
        "Alice", "Bob", "Operator_" + nonce, "Jane Doe", "user-42",
        "Status available", "Team Blue", "guest." + nonce[:8]
    ]

    cmd_attacks = [
        lambda t: f"echo {t}; id",
        lambda t: f"echo {t} && whoami",
        lambda t: f"echo {t} || uname -a",
        lambda t: f"printf {t} | sh",
        lambda t: f"echo $({t})",
        lambda t: f"echo `{t}`",
        lambda t: f"echo {t}\n/bin/sh",
        lambda t: f"echo {t};/bin/bash -c id",
    ]
    xss_attacks = [
        lambda t: f"<script>alert('{t}')</script>",
        lambda t: f"<ScRiPt src=//{t}.invalid/x.js></sCrIpT>",
        lambda t: f"<img src=x onerror=alert('{t}')>",
        lambda t: f"<svg/onload=confirm('{t}')>",
        lambda t: f"javascript:eval('{t}')",
        lambda t: f"JaVaScRiPt:alert('{t}')",
        lambda t: f"data:text/html,<script>alert('{t}')</script>",
        lambda t: f"<iframe srcdoc=\"<script>alert('{t}')</script>\"></iframe>",
    ]

    evil = []
    for i in range(96):
        token = nonce + secrets.token_hex(4) + str(i)
        if i % 2 == 0:
            obj = {
                "cmd_exec": rng.choice(cmd_attacks)(token),
                "user_profile_xss": rng.choice(safe_profiles),
                "request_id": token,
            }
        else:
            obj = {
                "cmd_exec": rng.choice(safe_commands),
                "user_profile_xss": rng.choice(xss_attacks)(token),
                "request_id": token,
            }
        evil.append(encoded_payload(obj, rng))

    clean = []
    for i in range(72):
        token = nonce + secrets.token_hex(4) + str(i)
        obj = {
            "cmd_exec": rng.choice(safe_commands),
            "user_profile_xss": rng.choice(safe_profiles),
            "request_id": token,
        }
        # Dangerous-looking text in an unrelated field does not target either
        # field consumed by the daemon and must not cause a false positive.
        if i % 9 == 0:
            obj["audit_note"] = f"literal example: <script>{token}</script>; | &&"
        clean.append(encoded_payload(obj, rng))

    malformed = [
        "", "{", "[] trailing", "not json", "{\"cmd_exec\":",
        "{\"cmd_exec\":\"echo ok\",}", "null trailing",
    ]

    for binary in sanitizer_bins:
        for index, payload in enumerate(evil):
            assert invoke(binary, payload) == 1, \
                f"{binary} accepted generated malicious payload #{index}"
        for index, payload in enumerate(clean):
            assert invoke(binary, payload) == 0, \
                f"{binary} rejected generated clean payload #{index}"
        for index, payload in enumerate(malformed):
            assert invoke(binary, payload) == 1, \
                f"{binary} did not safely reject malformed JSON #{index}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
