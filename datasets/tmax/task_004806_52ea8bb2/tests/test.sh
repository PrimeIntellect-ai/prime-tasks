#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import requests
import time
import subprocess
import tempfile
import re
import html
import secrets
import random


def public_key_from_file(path, passphrase):
    with tempfile.NamedTemporaryFile(delete=False) as tmp:
        with open(path, "rb") as src:
            tmp.write(src.read())
        temp_path = tmp.name
    try:
        os.chmod(temp_path, 0o600)
        result = subprocess.run(
            ["ssh-keygen", "-y", "-P", passphrase, "-f", temp_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        if result.returncode != 0:
            return None
        return result.stdout.strip()
    finally:
        os.unlink(temp_path)


def recover_source_public_key():
    result = subprocess.run(
        ["tesseract", "/app/sticky_note.png", "stdout"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, "Could not OCR the supplied sticky note"

    tokens = re.findall(r"[A-Za-z0-9]+", result.stdout)
    collapsed = "".join(result.stdout.split())
    if collapsed:
        tokens.append(collapsed)

    seen = set()
    for base in tokens:
        if base in seen:
            continue
        seen.add(base)
        for digit in "0123456789":
            public_key = public_key_from_file("/app/admin_key.enc", base + digit)
            if public_key is not None:
                return public_key
    assert False, "No passphrase derived from the sticky note decrypts /app/admin_key.enc"


def test_admin_key_decrypted():
    key_path = "/home/user/admin_key.pem"
    assert os.path.isfile(key_path), f"{key_path} is missing"
    with open(key_path, "r") as f:
        content = f.read()
    assert "ENCRYPTED" not in content, f"The key at {key_path} is still encrypted"
    assert "PRIVATE KEY" in content, f"The file at {key_path} does not look like a private key"

    submitted_public = public_key_from_file(key_path, "")
    assert submitted_public is not None, "The submitted key is not a valid unencrypted SSH private key"
    source_public = recover_source_public_key()
    assert submitted_public == source_public, "The submitted key does not match /app/admin_key.enc"


def test_ssh_audit_json():
    audit_path = "/home/user/ssh_audit.json"
    assert os.path.isfile(audit_path), f"{audit_path} is missing"
    with open(audit_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{audit_path} does not contain valid JSON"

    expected = {"PermitRootLogin": "no", "PasswordAuthentication": "no"}
    assert data == expected, f"Audit JSON content is incorrect. Expected {expected}, got {data}"


def test_service_post_log():
    payload = {"entry": '<script>alert("XSS & Injection")</script>'}
    try:
        r = requests.post("http://127.0.0.1:8080/log", data=payload, timeout=2)
    except requests.RequestException as e:
        assert False, f"Service not reachable or failed on POST /log: {e}"

    assert r.status_code == 200, f"Expected status 200 for POST /log, got {r.status_code}"

    time.sleep(0.5)
    log_path = "/home/user/service_audit.log"
    assert os.path.isfile(log_path), f"Log file {log_path} not created"

    with open(log_path, "r") as f:
        log_content = f.read()

    assert "&lt;script&gt;alert(" in log_content, "Log entry not found or '<' / '>' not properly HTML encoded"
    assert "&quot;XSS &amp; Injection&quot;" in log_content, "Log entry quotes or ampersands not properly HTML encoded"
    assert "&lt;/script&gt;" in log_content, "Log entry closing tags not properly HTML encoded"
    assert "<script>" not in log_content, "Unescaped HTML found in log"


def assert_strict_entity_encoding(original, encoded):
    dangerous = set('<>&"\'')
    pos = 0
    for char in original:
        if char not in dangerous:
            assert pos < len(encoded) and encoded[pos] == char, \
                f"Safe character {char!r} was lost or altered in logged output {encoded!r}"
            pos += 1
            continue

        assert pos < len(encoded) and encoded[pos] == "&", \
            f"Dangerous character {char!r} was not HTML-entity encoded in {encoded!r}"
        end = encoded.find(";", pos + 1)
        assert end != -1, f"Unterminated HTML entity in logged output {encoded!r}"
        entity = encoded[pos:end + 1]
        assert html.unescape(entity) == char and entity != char, \
            f"Entity {entity!r} does not encode expected character {char!r}"
        pos = end + 1

    assert pos == len(encoded), f"Logged entry contains unexpected extra content: {encoded!r}"


def test_service_post_log_randomized_and_appends_newlines():
    log_path = "/home/user/service_audit.log"
    with open(log_path, "wb") as f:
        f.write(b"existing-record\n")

    rng = random.SystemRandom()
    for _ in range(4):
        marker = secrets.token_hex(12)
        chars = list('<>&"\'') * 2
        rng.shuffle(chars)
        entry = marker + "-" + "SAFE".join(chars) + "-" + secrets.token_hex(8)

        with open(log_path, "rb") as f:
            before = f.read()

        try:
            response = requests.post(
                "http://127.0.0.1:8080/log",
                data={"entry": entry},
                timeout=2,
            )
        except requests.RequestException as e:
            assert False, f"Service failed randomized POST /log: {e}"
        assert response.status_code == 200, \
            f"Expected status 200 for randomized POST /log, got {response.status_code}"

        deadline = time.time() + 2
        after = before
        while time.time() < deadline:
            with open(log_path, "rb") as f:
                after = f.read()
            if len(after) > len(before):
                break
            time.sleep(0.05)

        assert after.startswith(before), "POST /log did not append to the existing audit log"
        appended = after[len(before):]
        assert appended.endswith(b"\n"), "Logged entry was not terminated by a newline"
        assert appended.count(b"\n") == 1, "A single entry must be appended as one new line"
        try:
            encoded = appended[:-1].decode("utf-8")
        except UnicodeDecodeError:
            assert False, "Logged entry is not valid UTF-8 text"
        assert_strict_entity_encoding(entry, encoded)


def test_service_get_report_auth():
    headers = {"Authorization": "Bearer ComplianceAdmin7"}
    try:
        r = requests.get("http://127.0.0.1:8080/report", headers=headers, timeout=2)
    except requests.RequestException as e:
        assert False, f"Service not reachable or failed on GET /report: {e}"

    assert r.status_code == 200, f"Expected status 200 for authenticated GET /report, got {r.status_code}"
    try:
        data = r.json()
    except ValueError:
        assert False, "Response to GET /report was not valid JSON"

    expected = {"PermitRootLogin": "no", "PasswordAuthentication": "no"}
    assert data == expected, f"Report endpoint returned incorrect JSON. Expected {expected}, got {data}"


def test_service_get_report_no_auth():
    try:
        r = requests.get("http://127.0.0.1:8080/report", timeout=2)
    except requests.RequestException as e:
        assert False, f"Service not reachable or failed on GET /report: {e}"

    assert r.status_code == 401, f"Expected status 401 for missing auth, got {r.status_code}"

    headers = {"Authorization": "Bearer WrongPass"}
    try:
        r2 = requests.get("http://127.0.0.1:8080/report", headers=headers, timeout=2)
    except requests.RequestException as e:
        assert False, f"Service not reachable or failed on GET /report: {e}"

    assert r2.status_code == 401, f"Expected status 401 for wrong auth, got {r2.status_code}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
