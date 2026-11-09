#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import secrets
import shutil
import subprocess
import tempfile
from collections import Counter

import pytest

REPORT_PATH = "/home/user/secrets_report.json"
KEY_PATH = "/home/user/fernet.key"
AUTH_PATH = "/home/user/auth_mock.py"
REPO_PATH = "/home/user/repo"


def test_secrets_report_exists_and_format():
    assert os.path.exists(REPORT_PATH), f"Verification failed: {REPORT_PATH} not found."

    with open(REPORT_PATH, "r") as r:
        try:
            data = json.load(r)
        except Exception as e:
            pytest.fail(f"Verification failed: Invalid JSON. {e}")

    assert isinstance(data, list), "Verification failed: JSON root must be a list."
    assert len(data) == 2, f"Verification failed: Expected 2 entries, found {len(data)}"

    assert "file" in data[0] and "encrypted_secret" in data[0], "Verification failed: Missing required keys in first entry."
    assert "file" in data[1] and "encrypted_secret" in data[1], "Verification failed: Missing required keys in second entry."

    assert data[0]["file"] == "app1.conf", f"Verification failed: Expected first file to be 'app1.conf', got '{data[0]['file']}'."
    assert data[1]["file"] == "app3.conf", f"Verification failed: Expected second file to be 'app3.conf', got '{data[1]['file']}'."


def test_secrets_decryption():
    assert os.path.exists(REPORT_PATH), f"Verification failed: {REPORT_PATH} not found."
    assert os.path.exists(KEY_PATH), f"Verification failed: {KEY_PATH} not found."

    with open(REPORT_PATH, "r") as r:
        data = json.load(r)

    secret1_enc = data[0]["encrypted_secret"]
    secret3_enc = data[1]["encrypted_secret"]

    script = f'''\nimport sys\ntry:\n    from cryptography.fernet import Fernet\nexcept ImportError:\n    print("cryptography library not found")\n    sys.exit(3)\n\nkey_path = {KEY_PATH!r}\nwith open(key_path, "rb") as f:\n    key = f.read().strip()\n\ntry:\n    fernet = Fernet(key)\nexcept Exception as e:\n    print(f"Invalid Fernet key: {{e}}")\n    sys.exit(4)\n\ntry:\n    secret1 = fernet.decrypt({secret1_enc!r}.encode("utf-8")).decode("utf-8")\n    secret3 = fernet.decrypt({secret3_enc!r}.encode("utf-8")).decode("utf-8")\nexcept Exception as e:\n    print(f"Decryption error: {{e}}")\n    sys.exit(2)\n\nif secret1 == "admin:supersecret123" and secret3 == "root:toor":\n    sys.exit(0)\nelse:\n    print(f"Decrypted secrets do not match. Got: {{secret1}} and {{secret3}}")\n    sys.exit(1)\n'''

    result = subprocess.run(["python3", "-c", script], capture_output=True, text=True)
    assert result.returncode == 0, f"Verification failed: {result.stdout.strip() or result.stderr.strip() or 'Decryption check failed.'}"


def _find_python_scripts():
    excluded = {os.path.realpath(AUTH_PATH), "/tmp/test_final_state.py"}
    candidates = []
    for root in ("/home/user", "/tmp", "/workspace"):
        if not os.path.isdir(root):
            continue
        for directory, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if d not in {"__pycache__", ".git"}]
            for filename in filenames:
                if not filename.endswith(".py"):
                    continue
                path = os.path.join(directory, filename)
                if os.path.realpath(path) in excluded or not os.path.isfile(path):
                    continue
                candidates.append(path)
    return sorted(set(candidates))


def test_scanner_script_executes_extraction_and_authentication():
    candidates = _find_python_scripts()
    assert candidates, "Verification failed: No Python scanner script was found."

    nonce = secrets.token_hex(8)
    valid_secrets = [f"svc_{nonce}:pw_{secrets.token_hex(6)}", f"ops_{nonce}:pw_{secrets.token_hex(6)}"]
    invalid_secrets = [f"guest_{nonce}:bad_{secrets.token_hex(6)}", f"old_{nonce}:bad_{secrets.token_hex(6)}"]
    valid_tokens = [base64.b64encode(s.encode()).decode() for s in valid_secrets]
    invalid_tokens = [base64.b64encode(s.encode()).decode() for s in invalid_secrets]
    distractor = base64.b64encode(f"ignored_{nonce}:ignored".encode()).decode()

    valid_files = [f"alpha_{nonce}.conf", f"zeta_{nonce}.conf"]
    invalid_files = [f"beta_{nonce}.conf", f"middle_{nonce}.conf"]
    expected = dict(zip(valid_files, valid_secrets))
    required_calls = valid_tokens + invalid_tokens
    log_path = f"/tmp/auth_calls_{nonce}.log"

    backup_dir = tempfile.mkdtemp(prefix="scanner_verify_")
    repo_backup = os.path.join(backup_dir, "repo")
    shutil.copytree(REPO_PATH, repo_backup)
    with open(AUTH_PATH, "rb") as f:
        auth_backup = f.read()
    with open(KEY_PATH, "rb") as f:
        key_backup = f.read()
    report_backup = None
    if os.path.exists(REPORT_PATH):
        with open(REPORT_PATH, "rb") as f:
            report_backup = f.read()

    auth_program = f'''import base64\nimport sys\nLOG = {log_path!r}\nVALID = {valid_secrets!r}\nif len(sys.argv) != 2:\n    sys.exit(1)\ntoken = sys.argv[1]\nwith open(LOG, "a") as log:\n    log.write(token + "\\n")\ntry:\n    decoded = base64.b64decode(token, validate=True).decode("utf-8")\nexcept Exception:\n    sys.exit(1)\nsys.exit(0 if decoded in VALID else 1)\n'''

    def reset_challenge():
        if os.path.exists(REPO_PATH):
            shutil.rmtree(REPO_PATH)
        shutil.copytree(repo_backup, REPO_PATH)
        for directory, _, filenames in os.walk(REPO_PATH):
            for filename in filenames:
                if filename.endswith(".conf"):
                    os.remove(os.path.join(directory, filename))

        files = {
            valid_files[0]: f"Server=dynamic\nAuthorization: Basic {valid_tokens[0]}\nPort=1\n",
            valid_files[1]: f"Authorization: Basic {valid_tokens[1]}\n",
            invalid_files[0]: f"Authorization: Basic {invalid_tokens[0]}\n",
            invalid_files[1]: f"Host=dynamic\nAuthorization: Basic {invalid_tokens[1]}\n",
            f"noise_{nonce}.conf": (
                f" Authorization: Basic {distractor}\n"
                f"authorization: Basic {distractor}\n"
                f"Prefix Authorization: Basic {distractor}\n"
            ),
        }
        for filename, content in files.items():
            with open(os.path.join(REPO_PATH, filename), "w") as f:
                f.write(content)

        with open(AUTH_PATH, "w") as f:
            f.write(auth_program)
        with open(KEY_PATH, "wb") as f:
            f.write(key_backup)
        if os.path.exists(REPORT_PATH):
            os.remove(REPORT_PATH)
        if os.path.exists(log_path):
            os.remove(log_path)

    failures = []
    passed = False
    try:
        for candidate in candidates:
            reset_challenge()
            try:
                result = subprocess.run(
                    ["python3", candidate],
                    cwd=os.path.dirname(candidate) or "/home/user",
                    capture_output=True,
                    text=True,
                    timeout=30,
                )
                assert result.returncode == 0, result.stderr.strip() or result.stdout.strip() or "script exited nonzero"
                assert os.path.isfile(REPORT_PATH), "script did not create secrets_report.json"

                with open(REPORT_PATH, "r") as f:
                    report = json.load(f)
                assert isinstance(report, list), "report root is not a list"
                assert [entry.get("file") for entry in report] == sorted(valid_files), "report has wrong files or ordering"
                assert all(set(entry) == {"file", "encrypted_secret"} for entry in report), "report entries have incorrect keys"

                from cryptography.fernet import Fernet
                with open(KEY_PATH, "rb") as f:
                    fernet = Fernet(f.read().strip())
                decrypted = {}
                for entry in report:
                    encrypted = entry["encrypted_secret"]
                    assert isinstance(encrypted, str), "encrypted_secret must be a string"
                    decrypted[entry["file"]] = fernet.decrypt(encrypted.encode("utf-8")).decode("utf-8")
                assert decrypted == expected, "reported secrets do not match the dynamically discovered valid tokens"

                assert os.path.isfile(log_path), "scanner did not invoke auth_mock.py"
                with open(log_path, "r") as f:
                    calls = [line.rstrip("\n") for line in f]
                counts = Counter(calls)
                assert all(counts[token] >= 1 for token in required_calls), "scanner did not authenticate every extracted token"
                assert counts[distractor] == 0, "scanner authenticated a line that did not start with the exact required prefix"
                passed = True
                break
            except Exception as e:
                failures.append(f"{candidate}: {e}")

        assert passed, "Verification failed: No scanner script passed dynamic execution. " + " | ".join(failures[-5:])
    finally:
        if os.path.exists(REPO_PATH):
            shutil.rmtree(REPO_PATH)
        shutil.copytree(repo_backup, REPO_PATH)
        with open(AUTH_PATH, "wb") as f:
            f.write(auth_backup)
        with open(KEY_PATH, "wb") as f:
            f.write(key_backup)
        if report_backup is None:
            if os.path.exists(REPORT_PATH):
                os.remove(REPORT_PATH)
        else:
            with open(REPORT_PATH, "wb") as f:
                f.write(report_backup)
        if os.path.exists(log_path):
            os.remove(log_path)
        shutil.rmtree(backup_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
