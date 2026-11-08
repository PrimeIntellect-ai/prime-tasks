#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import os
import json
import binascii
import zipfile
import pytest

ENC_PATH = "/home/user/forensics/payload.enc"
ZIP_PATH = "/home/user/forensics/payload.zip"
EXTRACTED_PATH = "/home/user/forensics/exfiltrated.json"
CLEAN_PATH = "/home/user/evidence_clean.json"


def derive_expected():
    with open(ENC_PATH, "r", encoding="ascii") as f:
        encrypted = binascii.unhexlify("".join(f.read().split()))

    magic = b"PK\x03\x04"
    assert len(encrypted) >= 4
    key = bytes(encrypted[i] ^ magic[i] for i in range(4))
    assert key[:2] == b"C2"
    assert all(32 <= b <= 126 for b in key[2:])

    decrypted = bytes(b ^ key[i % 4] for i, b in enumerate(encrypted))
    assert decrypted.startswith(magic)

    with zipfile.ZipFile(io.BytesIO(decrypted), "r") as archive:
        matching = [n for n in archive.namelist() if os.path.basename(n) == "exfiltrated.json"]
        assert len(matching) == 1
        with open("/home/user/wordlist.txt", "r", encoding="utf-8") as f:
            passwords = [line.rstrip("\r\n") for line in f]

        source = None
        for password in passwords:
            try:
                source = archive.read(matching[0], pwd=password.encode())
                break
            except (RuntimeError, zipfile.BadZipFile):
                pass
        assert source is not None, "No supplied dictionary password opens the recovered archive"

    return decrypted, source


EXPECTED_ZIP, EXPECTED_SOURCE = derive_expected()


def test_c2_ip_extracted():
    """Verify that the C2 IP address was correctly extracted from the firewall dump."""
    ip_file_path = "/home/user/c2_ip.txt"
    assert os.path.isfile(ip_file_path), f"Expected file {ip_file_path} is missing. Did you save the C2 IP?"

    with open(ip_file_path, "r") as f:
        ip_address = f.read().strip()

    assert ip_address == "192.168.100.45", f"Incorrect C2 IP extracted. Expected '192.168.100.45', but got '{ip_address}'."


def test_payload_zip_decrypted():
    """Verify that the payload was correctly XOR-decrypted and saved as a ZIP file."""
    zip_file_path = ZIP_PATH
    assert os.path.isfile(zip_file_path), f"Expected file {zip_file_path} is missing. Did the Go program decrypt the payload?"

    with open(zip_file_path, "rb") as f:
        magic_bytes = f.read(4)

    assert magic_bytes == b"PK\x03\x04", "The decrypted payload.zip does not start with the standard ZIP magic bytes (PK\\x03\\x04). The XOR decryption might be incorrect."
    with open(zip_file_path, "rb") as f:
        actual = f.read()
    assert actual == EXPECTED_ZIP, "payload.zip is not the complete, faithful decryption of payload.enc"
    with zipfile.ZipFile(io.BytesIO(actual), "r") as archive:
        assert any(os.path.basename(n) == "exfiltrated.json" for n in archive.namelist())


def test_exfiltrated_json_extracted():
    """Verify that the ZIP file was cracked and its contents extracted."""
    json_file_path = EXTRACTED_PATH
    assert os.path.isfile(json_file_path), f"Expected file {json_file_path} is missing. Did you crack the ZIP password and extract it?"
    with open(json_file_path, "rb") as f:
        assert f.read() == EXPECTED_SOURCE, "exfiltrated.json does not match the file in the decrypted, password-protected archive"


def test_evidence_clean_json_redacted():
    """Verify that the sensitive data was properly redacted and saved as valid JSON."""
    clean_file_path = CLEAN_PATH
    assert os.path.isfile(clean_file_path), f"Expected file {clean_file_path} is missing. Did you run the redaction program?"

    with open(clean_file_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {clean_file_path} does not contain valid JSON.")

    assert isinstance(data, list), "The redacted JSON data should be an array (list) of objects."
    assert len(data) == 2, f"Expected 2 records in the JSON array, but found {len(data)}."

    expected_usernames = {"admin", "jsmith"}
    found_usernames = set()

    for i, record in enumerate(data):
        assert isinstance(record, dict), f"Record at index {i} is not a JSON object."
        for field in ["id", "username", "email", "credit_card"]:
            assert field in record, f"Record at index {i} is missing the '{field}' field."
        assert record["credit_card"] == "[REDACTED]", f"The 'credit_card' field for user '{record.get('username')}' was not properly redacted. Expected '[REDACTED]', got '{record['credit_card']}'."
        found_usernames.add(record["username"])

    assert found_usernames == expected_usernames, "The usernames in the redacted JSON do not match the expected original records."

    original = json.loads(EXPECTED_SOURCE.decode("utf-8"))
    expected = []
    for record in original:
        record = dict(record)
        record["credit_card"] = "[REDACTED]"
        expected.append(record)
    assert data == expected, "evidence_clean.json is not a faithful field-for-field redaction of the extracted records"
TEST_EOF

cat << 'GO_TEST_EOF' > /tmp/test_go_programs.py
import io
import json
import os
import pwd
import shutil
import subprocess
import zipfile

ENC = "/home/user/forensics/payload.enc"
ZIP = "/home/user/forensics/payload.zip"
SOURCE = "/home/user/forensics/exfiltrated.json"
CLEAN = "/home/user/evidence_clean.json"
PATHS = [ENC, ZIP, SOURCE, CLEAN]


def snapshot():
    return {p: (open(p, "rb").read() if os.path.exists(p) else None) for p in PATHS}


def restore(saved):
    for path, content in saved.items():
        if content is None:
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
        else:
            with open(path, "wb") as f:
                f.write(content)
            os.chown(path, pwd.getpwnam("user").pw_uid, pwd.getpwnam("user").pw_gid)


def find_candidates(role):
    candidates = []
    seen = set()
    for root, dirs, files in os.walk("/home/user"):
        dirs[:] = [d for d in dirs if d not in {"go", ".cache", ".config"}]
        gofiles = [os.path.join(root, f) for f in files if f.endswith(".go")]
        if not gofiles:
            continue
        texts = {}
        for path in gofiles:
            try:
                texts[path] = open(path, "r", encoding="utf-8").read()
            except (OSError, UnicodeDecodeError):
                pass
        aggregate = "\n".join(texts.values())

        def relevant(text):
            low = text.lower()
            if role == "decrypt":
                return "payload.enc" in low and "payload.zip" in low and ("encoding/hex" in low or "hex.decode" in low) and "^" in text
            return "exfiltrated.json" in low and "evidence_clean.json" in low and "redacted" in low and "encoding/json" in low

        if relevant(aggregate):
            item = (root, ("go", "run", "."))
            if item not in seen:
                seen.add(item)
                candidates.append(item)
        for path, text in texts.items():
            if relevant(text):
                item = (os.path.dirname(path), ("go", "run", path))
                if item not in seen:
                    seen.add(item)
                    candidates.append(item)
    return candidates


def run_as_user(cwd, command):
    account = pwd.getpwnam("user")
    cache = "/tmp/verifier-go-cache"
    os.makedirs(cache, exist_ok=True)
    os.chown(cache, account.pw_uid, account.pw_gid)
    env = os.environ.copy()
    env.update({"HOME": "/home/user", "GOCACHE": cache, "GO111MODULE": "off"})

    def demote():
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    try:
        subprocess.run(command, cwd=cwd, env=env, stdout=subprocess.PIPE,
                       stderr=subprocess.PIPE, timeout=40, check=False,
                       preexec_fn=demote)
    except (subprocess.TimeoutExpired, OSError):
        pass


def make_test_zip():
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("probe.txt", "independent verifier probe\n")
    return buf.getvalue()


def verify_decrypt_program(saved):
    candidates = find_candidates("decrypt")
    assert candidates, "No Go source implementing the required XOR/hex decryption was found"
    plain = make_test_zip()
    key = b"C2~Q"
    encrypted = bytes(b ^ key[i % 4] for i, b in enumerate(plain)).hex().encode("ascii")

    for cwd, command in candidates:
        restore(saved)
        with open(ENC, "wb") as f:
            f.write(encrypted)
        try:
            os.remove(ZIP)
        except FileNotFoundError:
            pass
        run_as_user(cwd, command)
        if os.path.isfile(ZIP) and open(ZIP, "rb").read() == plain:
            return
    raise AssertionError("The submitted Go decryption program did not decrypt an independent 4-byte-key ZIP payload")


def verify_redaction_program(saved):
    candidates = find_candidates("redact")
    assert candidates, "No Go source implementing the required JSON redaction was found"
    records = [
        {"id": 814, "username": "probe_alpha", "email": "alpha@example.test", "credit_card": "9012-3456-7890-1234"},
        {"id": 27, "username": "probe_beta", "email": "beta@example.test", "credit_card": "4444-3333-2222-1111"}
    ]
    expected = [dict(r, credit_card="[REDACTED]") for r in records]

    for cwd, command in candidates:
        restore(saved)
        with open(SOURCE, "w", encoding="utf-8") as f:
            json.dump(records, f)
        try:
            os.remove(CLEAN)
        except FileNotFoundError:
            pass
        run_as_user(cwd, command)
        try:
            with open(CLEAN, "r", encoding="utf-8") as f:
                actual = json.load(f)
        except (OSError, ValueError):
            continue
        if actual == expected:
            return
    raise AssertionError("The submitted Go redaction program did not faithfully redact independent JSON records")


saved = snapshot()
try:
    verify_decrypt_program(saved)
    verify_redaction_program(saved)
finally:
    restore(saved)
GO_TEST_EOF

ok=1
python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 || ok=0
if [ "$ok" -eq 1 ]; then
    python3 /tmp/test_go_programs.py 2>&1 || ok=0
fi

if [ "$ok" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
