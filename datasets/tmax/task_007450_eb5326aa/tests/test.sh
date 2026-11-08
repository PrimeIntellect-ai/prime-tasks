#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import string
import subprocess
import tempfile

PARSER = "/home/user/parser.py"
EVENTS = "/home/user/events.dat"
AUTH_SERVICE = "/home/user/auth_service"
RECOVERED_EVENT = "/home/user/recovered_event.txt"
EXPECTED_EVENT = "CRITICAL_FAILURE_AT_NODE_77"


def run_parser(input_path, key):
    result = subprocess.run(
        ["python3", PARSER, input_path, key],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"Recovered parser failed with exit code {result.returncode}: {result.stderr}"
    )
    return result.stdout.strip()


def extract_key():
    with open(AUTH_SERVICE, "rb") as f:
        binary = f.read()
    matches = re.findall(rb"SECRET_AUTH_KEY_[A-Za-z0-9]+", binary)
    assert matches, "No legacy fallback key was found in auth_service."
    return matches[0].decode("ascii")


def test_recovered_event_file_exists():
    path = RECOVERED_EVENT
    assert os.path.isfile(path), f"File {path} does not exist. The decoded event string was not saved."


def test_recovered_event_content():
    path = RECOVERED_EVENT
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, "r", encoding="utf-8") as f:
        content = f.read().strip()

    expected = EXPECTED_EVENT
    assert content == expected, f"Expected the recovered event to be '{expected}', but got '{content}'."


def test_parser_script_recovered():
    path = PARSER
    assert os.path.isfile(path), f"File {path} does not exist. The python script was not recovered from the memdump."

    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        content = f.read()

    assert "def decode(" in content, "The recovered parser.py does not contain the expected 'decode' function."


def test_recovered_parser_decodes_random_payload():
    alphabet = string.ascii_uppercase + string.digits + "_"
    plaintext = "".join(secrets.choice(alphabet) for _ in range(47))
    key = "TEST_KEY_" + "".join(secrets.choice(string.ascii_letters + string.digits) for _ in range(19))
    ciphertext = bytes(ord(c) ^ ord(key[i % len(key)]) for i, c in enumerate(plaintext))

    with tempfile.NamedTemporaryFile(mode="wb", delete=False) as f:
        f.write(ciphertext)
        test_input = f.name

    try:
        assert run_parser(test_input, key) == plaintext, (
            "Recovered parser.py did not correctly decode an independently generated payload."
        )
    finally:
        os.unlink(test_input)


def test_recovered_parser_decodes_incident_event():
    key = extract_key()
    with open(EVENTS, "rb") as f:
        data = f.read()

    first_ascii = 0
    while first_ascii < len(data) and data[first_ascii] >= 128:
        first_ascii += 1
    assert first_ascii > 0, "events.dat does not contain the expected leading corruption."
    cleaned = data[first_ascii:]
    assert cleaned, "No event payload remained after removing the leading corruption."
    cleaned.decode("ascii")

    with tempfile.NamedTemporaryFile(mode="wb", delete=False) as f:
        f.write(cleaned)
        cleaned_path = f.name

    try:
        decoded = run_parser(cleaned_path, key)
    finally:
        os.unlink(cleaned_path)

    assert decoded == EXPECTED_EVENT, (
        f"Recovered parser decoded the incident payload as {decoded!r}, not {EXPECTED_EVENT!r}."
    )
    with open(RECOVERED_EVENT, "r", encoding="utf-8") as f:
        saved = f.read().strip()
    assert decoded == saved, "recovered_event.txt does not match the recovered parser's output."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
