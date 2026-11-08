#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import base64


def get_encoded_password(password: str) -> str:
    # The script encode_pass.sh does: echo -n "$1" | base64 | rev
    b64 = base64.b64encode(password.encode("utf-8")).decode("utf-8")
    return b64[::-1]


EXPECTED_PASSWORD = "SuperSecretRotate2024!"
EXPECTED_ENCODED = get_encoded_password(EXPECTED_PASSWORD)
EXPECTED_CONFIG_LINES = [
    "[database]",
    "DB_HOST=127.0.0.1",
    "DB_PORT=5432",
    "DB_USER=admin",
    f"DB_PASS={EXPECTED_ENCODED}",
]
EXPECTED_SUDOERS_LINE = (
    "app_user ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart legacy_app"
)
EXPECTED_IPTABLES_LINES = [
    "*filter",
    ":INPUT DROP [0:0]",
    ":FORWARD DROP [0:0]",
    ":OUTPUT ACCEPT [0:0]",
    "-A INPUT -p tcp -m tcp --dport 22 -j ACCEPT",
    "-A INPUT -p tcp -m tcp -s 10.50.100.5 --dport 8080 -j ACCEPT",
    "-A INPUT -p tcp -m tcp --dport 443 -j ACCEPT",
    "COMMIT",
]
EXPECTED_RULE = EXPECTED_IPTABLES_LINES[5]


def test_config_ini_updated():
    config_path = "/home/user/legacy_app/config.ini"
    assert os.path.exists(config_path), f"{config_path} is missing."

    with open(config_path, "r") as f:
        lines = f.readlines()

    db_pass_line = None
    for line in lines:
        if line.startswith("DB_PASS="):
            db_pass_line = line.strip()
            break

    assert db_pass_line is not None, "DB_PASS line missing from config.ini."
    assert db_pass_line == f"DB_PASS={EXPECTED_ENCODED}", (
        f"DB_PASS was not correctly updated. Found: {db_pass_line}"
    )

    actual_lines = [line.rstrip("\r\n") for line in lines]
    assert actual_lines == EXPECTED_CONFIG_LINES, (
        "config.ini must retain every original line and ordering, with only "
        "the DB_PASS value changed."
    )


def test_sudoers_app_updated():
    sudoers_path = "/home/user/audit/sudoers_app"
    assert os.path.exists(sudoers_path), f"{sudoers_path} is missing."

    with open(sudoers_path, "r") as f:
        content = f.read().strip()

    assert "/bin/bash" not in content and "/bin/sh" not in content, (
        "Privilege escalation binary (e.g., /bin/bash) was not removed from sudoers_app."
    )
    expected_line = EXPECTED_SUDOERS_LINE
    assert expected_line in content, (
        "Legitimate service restart script altered or missing. "
        f"Expected to find: {expected_line}"
    )

    assert content.splitlines() == [EXPECTED_SUDOERS_LINE], (
        "sudoers_app must contain only the preserved legacy_app restart permission; "
        "unexpected commands or additional sudo rules are not allowed."
    )


def test_iptables_rules_updated():
    iptables_path = "/home/user/firewall/iptables.rules"
    assert os.path.exists(iptables_path), f"{iptables_path} is missing."

    with open(iptables_path, "r") as f:
        lines = [line.strip() for line in f.readlines()]

    port_8080_rules = [line for line in lines if "8080" in line]
    assert len(port_8080_rules) > 0, "No rule found for port 8080 in iptables.rules."

    for rule in port_8080_rules:
        assert "0.0.0.0/0" not in rule, (
            f"0.0.0.0/0 was not removed from the 8080 rule: {rule}"
        )

    expected_rule = EXPECTED_RULE
    assert expected_rule in lines, (
        f"Expected rule not found in iptables.rules: {expected_rule}"
    )

    assert lines == EXPECTED_IPTABLES_LINES, (
        "iptables.rules must preserve the original policy and change only the "
        "source of the existing port 8080 rule; unexpected rules or policy changes found."
    )


def test_rotation_log():
    log_path = "/home/user/rotation_log.txt"
    assert os.path.exists(log_path), f"{log_path} is missing."

    with open(log_path, "r") as f:
        raw_lines = f.read().splitlines()
    lines = [line.strip() for line in raw_lines if line.strip()]

    assert len(lines) >= 3, (
        f"rotation_log.txt should have at least 3 lines. Found {len(lines)}."
    )

    expected_line1 = EXPECTED_ENCODED
    expected_line2 = EXPECTED_RULE
    expected_line3 = EXPECTED_SUDOERS_LINE

    assert lines[0] == expected_line1, (
        f"Log Line 1 incorrect. Expected '{expected_line1}', got '{lines[0]}'."
    )
    assert lines[1] == expected_line2, (
        f"Log Line 2 incorrect. Expected '{expected_line2}', got '{lines[1]}'."
    )
    assert lines[2] == expected_line3, (
        f"Log Line 3 incorrect. Expected '{expected_line3}', got '{lines[2]}'."
    )

    assert raw_lines == [expected_line1, expected_line2, expected_line3], (
        "rotation_log.txt must contain exactly the three requested lines."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
