#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import copy
import json
import os
import stat

SOURCE = "/home/user/traffic.json"
CLEAN = "/home/user/clean_traffic.json"
BLOCKED = "/home/user/blocked_ips.txt"


def load_json(path):
    assert os.path.exists(path), f"File {path} is missing."
    assert os.path.isfile(path), f"{path} is not a file."
    with open(path, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            assert False, f"{path} does not contain valid JSON."


def derive_expected(source):
    expected = copy.deepcopy(source)
    blocked = set()

    for record in expected:
        headers = record["headers"]
        if "Authorization" in headers:
            headers["Authorization"] = "[REDACTED]"

        if "Set-Cookie" in headers:
            cookie = headers["Set-Cookie"]
            insecure = (
                not isinstance(cookie, str)
                or "secure" not in cookie.lower()
                or "httponly" not in cookie.lower()
            )
            if insecure:
                headers["Set-Cookie"] = "[REDACTED]"
                blocked.add(record["ip"])

    return expected, sorted(blocked)


def test_clean_traffic_permissions_and_existence():
    """Test that clean_traffic.json exists and has 0600 permissions."""
    assert os.path.exists(CLEAN), f"File {CLEAN} is missing."
    assert os.path.isfile(CLEAN), f"{CLEAN} is not a file."

    permissions = stat.S_IMODE(os.stat(CLEAN).st_mode)
    assert permissions == 0o600, (
        f"Permissions of {CLEAN} are {oct(permissions)}, expected 0o600."
    )


def test_clean_traffic_contents():
    """Retain the original record-level redaction assertions."""
    data = load_json(CLEAN)
    assert len(data) == 4, f"Expected 4 records in {CLEAN}, got {len(data)}."

    assert data[0]["ip"] == "192.168.1.50"
    assert data[0]["headers"].get("Authorization") == "[REDACTED]", "Authorization header not redacted in record 0."
    assert data[0]["headers"].get("Set-Cookie") == "[REDACTED]", "Set-Cookie missing 'Secure' not redacted in record 0."

    assert data[1]["ip"] == "10.0.0.5"
    assert data[1]["headers"].get("Set-Cookie") == "track_id=xyz987; Secure; HttpOnly", "Valid Set-Cookie was incorrectly modified in record 1."

    assert data[2]["ip"] == "172.16.0.10"
    assert data[2]["headers"].get("Set-Cookie") == "[REDACTED]", "Set-Cookie missing both directives not redacted in record 2."

    assert data[3]["ip"] == "192.168.1.50"
    assert data[3]["headers"].get("Authorization") == "[REDACTED]", "Authorization header not redacted in record 3."
    assert data[3]["headers"].get("Set-Cookie") == "[REDACTED]", "Set-Cookie missing 'HttpOnly' not redacted in record 3."


def test_complete_transformation_matches_source():
    """Compare every record and field with a transformation derived from the input."""
    source = load_json(SOURCE)
    actual = load_json(CLEAN)
    expected, _ = derive_expected(source)
    assert actual == expected, (
        "clean_traffic.json must preserve the complete input structure and all "
        "untouched values while applying only the required redactions."
    )


def test_blocked_ips_contents():
    """Test the original expected list and the list derived from the source."""
    assert os.path.exists(BLOCKED), f"File {BLOCKED} is missing."
    assert os.path.isfile(BLOCKED), f"{BLOCKED} is not a file."

    with open(BLOCKED, "r") as f:
        ips = [line.strip() for line in f if line.strip()]

    original_expected_ips = ["172.16.0.10", "192.168.1.50"]
    assert ips == original_expected_ips, (
        f"Blocked IPs incorrect. Expected {original_expected_ips}, got {ips}."
    )

    source = load_json(SOURCE)
    _, derived_expected_ips = derive_expected(source)
    assert ips == derived_expected_ips, (
        f"Blocked IPs do not match insecure-cookie records in {SOURCE}. "
        f"Expected {derived_expected_ips}, got {ips}."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
