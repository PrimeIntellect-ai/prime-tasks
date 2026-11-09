#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import string
import subprocess
import urllib.parse
import pytest

BUILDER_SCRIPT = "/home/user/builder.sh"
PAYLOAD_FILE = "/home/user/payload.http"
ELF_FILE = "/home/user/target_auth.elf"
WAF_RULES_FILE = "/home/user/waf_rules.txt"
EXPECTED_COOKIE = None

@pytest.fixture(scope="session", autouse=True)
def run_builder():
    """Randomize the ELF cookie, then run the builder script."""
    global EXPECTED_COOKIE

    assert os.path.exists(BUILDER_SCRIPT), f"{BUILDER_SCRIPT} does not exist."
    assert os.path.isfile(BUILDER_SCRIPT), f"{BUILDER_SCRIPT} is not a regular file."
    assert os.access(BUILDER_SCRIPT, os.X_OK), f"{BUILDER_SCRIPT} is not executable."

    with open(ELF_FILE, "rb") as f:
        original_elf = f.read()

    match = re.search(rb"SEC_COOKIE_[a-zA-Z0-9]{16}", original_elf)
    assert match, "Could not find a cookie key in the supplied ELF."
    old_cookie = match.group(0)

    alphabet = string.ascii_letters + string.digits
    while True:
        randomized = ("SEC_COOKIE_" + "".join(secrets.choice(alphabet) for _ in range(16))).encode("ascii")
        if randomized != old_cookie and randomized not in original_elf:
            break

    challenged_elf = original_elf.replace(old_cookie, randomized)
    EXPECTED_COOKIE = randomized.decode("ascii")

    try:
        with open(ELF_FILE, "wb") as f:
            f.write(challenged_elf)

        if os.path.lexists(PAYLOAD_FILE):
            os.unlink(PAYLOAD_FILE)

        try:
            subprocess.run([BUILDER_SCRIPT], check=True, capture_output=True, text=True, timeout=30)
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Execution of {BUILDER_SCRIPT} failed:\nSTDOUT: {e.stdout}\nSTDERR: {e.stderr}")
        except subprocess.TimeoutExpired:
            pytest.fail(f"Execution of {BUILDER_SCRIPT} timed out.")

        with open(ELF_FILE, "rb") as f:
            assert f.read() == challenged_elf, "Builder modified the supplied ELF artifact."

        yield
    finally:
        with open(ELF_FILE, "wb") as f:
            f.write(original_elf)


def get_expected_cookie():
    """Extract the expected cookie dynamically from the challenged ELF file."""
    try:
        output = subprocess.check_output(["strings", ELF_FILE]).decode("utf-8", errors="ignore")
        match = re.search(r"(SEC_COOKIE_[a-zA-Z0-9]{16})", output)
        if match:
            return match.group(1)
    except Exception:
        pass
    return None


def get_waf_blocked_uas():
    """Extract blocked User-Agents from WAF rules."""
    blocked_uas = []
    if os.path.exists(WAF_RULES_FILE):
        with open(WAF_RULES_FILE, "r") as f:
            for line in f:
                match = re.search(r"Block: User-Agent: \.\*(.*?)\.\*", line)
                if match:
                    blocked_uas.append(match.group(1).lower())
    return blocked_uas


def test_payload_file_exists():
    assert os.path.exists(PAYLOAD_FILE), f"Payload file {PAYLOAD_FILE} was not generated."
    assert os.path.isfile(PAYLOAD_FILE), f"{PAYLOAD_FILE} is not a regular file."


def test_payload_crlf_line_endings():
    with open(PAYLOAD_FILE, "rb") as f:
        content = f.read()

    content_no_crlf = content.replace(b"\r\n", b"")
    assert b"\n" not in content_no_crlf, "Payload contains LF line endings instead of strict CRLF."
    assert b"\r" not in content_no_crlf, "Payload contains a standalone CR instead of strict CRLF."


def test_payload_request_line_and_evasion():
    with open(PAYLOAD_FILE, "rb") as f:
        content = f.read().decode("utf-8", errors="ignore")

    lines = content.split("\r\n")
    request_line = lines[0]

    assert request_line.startswith("GET /login?"), "Payload does not start with 'GET /login?'."
    assert "next=" in request_line, "Payload missing 'next' parameter in request line."
    assert "http://" not in request_line, "Payload triggered WAF rule: contains 'http://'."
    assert "https://" not in request_line, "Payload triggered WAF rule: contains 'https://'."
    assert "attacker.com/pwn" in request_line, "Payload does not redirect to attacker.com/pwn."

    request_match = re.fullmatch(r"GET (\S+) HTTP/1\.1", request_line)
    assert request_match, "Request line must be a correctly formatted HTTP/1.1 GET request."

    request_target = request_match.group(1)
    parsed_target = urllib.parse.urlsplit(request_target)
    assert parsed_target.path == "/login", "GET request must target the /login path."

    query = urllib.parse.parse_qs(parsed_target.query, keep_blank_values=True)
    assert "next" in query and len(query["next"]) == 1, "Request must contain exactly one next parameter."

    redirect = urllib.parse.urlsplit(query["next"][0])
    assert redirect.hostname == "attacker.com", "The next parameter is not a valid URL targeting attacker.com."
    assert redirect.path == "/pwn", "The next parameter must redirect to /pwn on attacker.com."


def test_payload_headers():
    with open(PAYLOAD_FILE, "rb") as f:
        content = f.read().decode("utf-8", errors="ignore")

    assert "Host: vulnerable.local\r\n" in content, "Payload missing correct Host header."

    expected_cookie = get_expected_cookie()
    assert expected_cookie is not None, "Could not extract cookie from ELF for verification."
    assert expected_cookie == EXPECTED_COOKIE, "The challenged ELF does not contain the randomized cookie."

    expected_cookie_header = f"Cookie: {expected_cookie}=admin_bypass\r\n"
    assert expected_cookie_header in content, f"Payload missing correct Cookie header: {expected_cookie_header.strip()}"


def test_payload_user_agent_not_blocked():
    with open(PAYLOAD_FILE, "rb") as f:
        content = f.read().decode("utf-8", errors="ignore")

    ua_match = re.search(r"User-Agent:\s*(.*?)\r\n", content, re.IGNORECASE)
    assert ua_match, "Payload missing User-Agent header."

    ua_value = ua_match.group(1).lower()
    blocked_uas = get_waf_blocked_uas()

    for blocked in blocked_uas:
        assert blocked not in ua_value, f"Payload uses a blocked User-Agent containing '{blocked}'."


def test_payload_trailing_crlf():
    with open(PAYLOAD_FILE, "rb") as f:
        content = f.read()

    assert content.endswith(b"\r\n\r\n"), "Payload does not end with an empty line (trailing CRLF) to signify end of headers."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
