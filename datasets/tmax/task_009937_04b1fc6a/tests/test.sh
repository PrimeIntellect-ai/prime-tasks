#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
from collections import Counter

APP_LOG_PATH = "/home/user/app.log"
CONFIG_INI_PATH = "/home/user/config.ini"
NEW_KEY_PATH = "/home/user/new_key.txt"
OLD_KEY = "DEADc0ffee123456"

EXPECTED_LOG = """[INFO] Application started
[DEBUG] Checking token: [REDACTED]
[INFO] User authenticated successfully
[ERROR] Failed to validate backup token [REDACTED] - timeout
[INFO] Shutting down
"""


def read_text(path):
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def get_new_key():
    assert os.path.isfile(NEW_KEY_PATH), f"File {NEW_KEY_PATH} does not exist."
    raw = read_text(NEW_KEY_PATH)
    assert re.fullmatch(r"[0-9a-f]{32}\n?", raw), (
        f"{NEW_KEY_PATH} must contain only a 32-character lowercase hex key "
        "and an optional newline."
    )
    return raw.rstrip("\n")


def test_app_log_redacted():
    assert os.path.isfile(APP_LOG_PATH), f"File {APP_LOG_PATH} does not exist."
    content = read_text(APP_LOG_PATH)

    redacted_count = content.count("[REDACTED]")
    assert redacted_count == 2, (
        f"Expected exactly 2 instances of '[REDACTED]' in {APP_LOG_PATH}, "
        f"found {redacted_count}."
    )
    assert OLD_KEY not in content, f"Old key {OLD_KEY} is still present in {APP_LOG_PATH}."
    weak_keys = re.findall(r"DEAD[0-9a-f]{12}", content)
    assert not weak_keys, f"Found unredacted weak keys in {APP_LOG_PATH}: {weak_keys}"

    assert content == EXPECTED_LOG, (
        "app.log was not preserved while redacting the two weak-key occurrences."
    )


def test_new_key_generated():
    new_key = get_new_key()

    assert len(new_key) == 32, f"Expected new key to be 32 characters long, got {len(new_key)}."
    assert re.match(r"^[0-9a-f]{32}$", new_key), (
        f"New key '{new_key}' is not a valid 32-character lowercase hex string."
    )

    # Reject obvious fixed placeholders and low-diversity/repeating values. These
    # sanity checks distinguish a plausible random credential from values such as
    # 32 zeroes while retaining effectively all securely generated keys.
    assert len(set(new_key)) >= 8, "New key has implausibly low symbol diversity."
    counts = Counter(new_key)
    entropy = -sum((n / 32.0) * math.log2(n / 32.0) for n in counts.values())
    assert entropy >= 3.0, "New key has implausibly low hexadecimal entropy."
    assert not re.fullmatch(r"(.{1,8})\1+", new_key), "New key is a repeated fixed pattern."
    assert new_key not in {
        "0123456789abcdef0123456789abcdef",
        "abcdef0123456789abcdef0123456789",
        "deadbeefdeadbeefdeadbeefdeadbeef",
    }, "New key is a known placeholder value."


def test_config_ini_updated():
    assert os.path.isfile(CONFIG_INI_PATH), f"File {CONFIG_INI_PATH} does not exist."
    assert os.path.isfile(NEW_KEY_PATH), f"File {NEW_KEY_PATH} does not exist."
    new_key = get_new_key()
    content = read_text(CONFIG_INI_PATH)

    assert OLD_KEY not in content, f"Old key {OLD_KEY} is still present in {CONFIG_INI_PATH}."
    expected_line = f"API_KEY={new_key}"
    assert expected_line in content, f"Expected '{expected_line}' not found in {CONFIG_INI_PATH}."

    expected_config = f"""[Server]
Port=8080
Host=127.0.0.1

[Authentication]
API_KEY={new_key}
Timeout=30
"""
    assert content == expected_config, (
        "config.ini was not preserved while replacing the API_KEY value."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
