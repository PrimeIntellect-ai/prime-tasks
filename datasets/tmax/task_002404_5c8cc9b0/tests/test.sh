#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import csv
import json
import os
import pwd
import re
import secrets
import shutil
import socket
import stat
import subprocess
import tempfile
import time

import paramiko
import pytest


def test_ssh_config_hardened():
    sshd_config_path = "/app/sshd/sshd_config"
    assert os.path.isfile(sshd_config_path), f"Missing file: {sshd_config_path}"

    with open(sshd_config_path, "r") as f:
        content = f.read()

    # Preserve the original textual assertions.
    assert "PasswordAuthentication no" in content, "PasswordAuthentication is not explicitly disabled in sshd_config."
    assert "PubkeyAuthentication yes" in content, "PubkeyAuthentication is not enabled in sshd_config."

    os.makedirs("/run/sshd", exist_ok=True)
    result = subprocess.run(
        ["/usr/sbin/sshd", "-T", "-f", sshd_config_path,
         "-C", "user=user,host=localhost,addr=127.0.0.1"],
        capture_output=True, text=True
    )
    assert result.returncode == 0, f"Invalid sshd configuration: {result.stderr}"

    effective = {}
    for line in result.stdout.splitlines():
        parts = line.split(None, 1)
        if len(parts) == 2:
            effective[parts[0].lower()] = parts[1].strip()

    assert effective.get("port") == "2222", f"Effective SSH port is not 2222: {effective.get('port')}"
    assert effective.get("passwordauthentication") == "no", "Password authentication is enabled in the effective configuration."
    assert effective.get("pubkeyauthentication") == "yes", "Public-key authentication is disabled in the effective configuration."
    auth_files = effective.get("authorizedkeysfile", "").split()
    assert "/app/sshd/authorized_keys" in auth_files, f"Wrong effective AuthorizedKeysFile: {auth_files}"


def test_ssh_keys_generated():
    private_key_path = "/home/user/.ssh/id_rsa"
    public_key_path = "/home/user/.ssh/id_rsa.pub"
    authorized_keys_path = "/app/sshd/authorized_keys"

    assert os.path.isfile(private_key_path), f"SSH private key not found at {private_key_path}"
    assert os.path.isfile(public_key_path), f"SSH public key not found at {public_key_path}"
    assert os.path.isfile(authorized_keys_path), f"Authorized keys file not found at {authorized_keys_path}"

    user_uid = pwd.getpwnam("user").pw_uid
    assert os.stat(private_key_path).st_uid == user_uid, "The private key is not owned by user."
    assert os.stat(public_key_path).st_uid == user_uid, "The public key is not owned by user."
    assert stat.S_IMODE(os.stat("/home/user/.ssh").st_mode) == 0o700, "/home/user/.ssh must have mode 0700."
    assert stat.S_IMODE(os.stat(private_key_path).st_mode) == 0o600, "The private key must have mode 0600."
    assert stat.S_IMODE(os.stat(authorized_keys_path).st_mode) == 0o600, "authorized_keys must have mode 0600."

    derived = subprocess.run(
        ["ssh-keygen", "-y", "-f", private_key_path],
        input="", capture_output=True, text=True, timeout=5
    )
    assert derived.returncode == 0, "The private key is invalid or protected by a passphrase."
    derived_parts = derived.stdout.strip().split()
    assert len(derived_parts) >= 2

    with open(public_key_path) as f:
        public_parts = f.read().strip().split()
    assert len(public_parts) >= 2
    assert public_parts[:2] == derived_parts[:2], "id_rsa.pub does not correspond to id_rsa."

    matching_authorized_key = False
    with open(authorized_keys_path) as f:
        for line in f:
            parts = line.strip().split()
            for i in range(max(0, len(parts) - 1)):
                if parts[i:i + 2] == derived_parts[:2]:
                    matching_authorized_key = True
    assert matching_authorized_key, "authorized_keys does not contain the generated public key."


def test_flask_app_no_password():
    flask_app_path = "/app/backend/flask_app.py"
    assert os.path.isfile(flask_app_path), f"Missing file: {flask_app_path}"

    with open(flask_app_path, "r") as f:
        content = f.read()

    assert "supersecret123" not in content, "Hardcoded password still present in flask_app.py"
    assert "--password" not in content, "Password argument still being passed in flask_app.py"


def test_helper_no_password():
    helper_path = "/app/backend/helper.py"
    assert os.path.isfile(helper_path), f"Missing file: {helper_path}"

    with open(helper_path, "r") as f:
        content = f.read()

    assert "supersecret123" not in content, "Hardcoded password still present in helper.py"
    assert "password=" not in content.replace(" ", ""), "Password authentication appears to be used in helper.py"


def test_ids_filter_adversarial_corpus():
    script_path = "/home/user/ids_filter.py"
    evil_corpus_dir = "/home/user/corpora/evil"
    clean_corpus_dir = "/home/user/corpora/clean"

    assert os.path.isfile(script_path), f"IDS filter script missing at {script_path}"
    assert os.path.isdir(evil_corpus_dir), f"Evil corpus missing at {evil_corpus_dir}"
    assert os.path.isdir(clean_corpus_dir), f"Clean corpus missing at {clean_corpus_dir}"

    with tempfile.TemporaryDirectory() as temp_dir:
        staging_dir = os.path.join(temp_dir, "input")
        os.mkdir(staging_dir)
        expected = {}

        # Preserve testing of all originally supplied corpus files.
        for label, source_dir in (("evil", evil_corpus_dir), ("clean", clean_corpus_dir)):
            for name in os.listdir(source_dir):
                source = os.path.join(source_dir, name)
                if os.path.isfile(source) and name.endswith(".txt"):
                    assert name not in expected, f"Duplicate supplied corpus filename: {name}"
                    shutil.copy(source, os.path.join(staging_dir, name))
                    expected[name] = label

        cases = []
        clean_values = [
            ("administrator", "ls -la"),
            ("evil_named_user", "printf harmless"),
            ("clean", "path/without/traversal"),
            ("dots", ".."),
            ("slashes", "/tmp/safe/file"),
            ("spaces allowed", "echo ordinary words"),
            ("unicode-用户", "read café"),
        ]
        for username, command in clean_values:
            cases.append((username, command, "clean"))

        dangerous = [";", "&", "|", "$", "`", "<", ">", "../"]
        for token in dangerous:
            cases.append((f"prefix{token}suffix", "ordinary command", "evil"))
            cases.append(("ordinary-user", f"prefix{token}suffix", "evil"))

        # Random, semantically meaningless names prevent filename-based answers.
        for username, command, label in cases:
            while True:
                name = f"{secrets.token_hex(12)}.txt"
                if name not in expected:
                    break
            document = json.dumps({"username": username, "command": command}, ensure_ascii=False)
            encoded = base64.b64encode(document.encode("utf-8"))
            with open(os.path.join(staging_dir, name), "wb") as f:
                f.write(encoded + b"\n")
            expected[name] = label

        results_csv = os.path.join(temp_dir, "results.csv")
        result = subprocess.run(
            ["python3", script_path, staging_dir, results_csv],
            capture_output=True, text=True, timeout=15
        )
        assert result.returncode == 0, f"IDS filter script failed with error:\n{result.stderr}"
        assert os.path.isfile(results_csv), f"Output CSV not created at {results_csv}"

        rows = []
        with open(results_csv, newline="") as f:
            reader = csv.reader(f)
            header = next(reader, None)
            assert header == ["filename", "label"], f"Invalid CSV header: {header}"
            rows = list(reader)

        assert all(len(row) == 2 for row in rows), "Every CSV data row must contain exactly two columns."
        names = [row[0] for row in rows]
        assert len(names) == len(set(names)), "The output contains duplicate filenames."
        assert set(names) == set(expected), "The output must contain exactly one row for every input .txt file."
        for name, label in rows:
            assert label in {"clean", "evil"}, f"Invalid label for {name}: {label}"
            assert label == expected[name], f"Incorrect classification for {name}: expected {expected[name]}, got {label}"


def wait_for_port(port, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.3):
                return
        except OSError:
            time.sleep(0.1)
    pytest.fail(f"Port {port} did not become ready")


def curl_trigger():
    return subprocess.run(
        ["curl", "-s", "http://127.0.0.1:8080/trigger"],
        capture_output=True, text=True, timeout=8
    )


def test_end_to_end_services():
    start_script = "/app/start_services.sh"
    assert os.path.isfile(start_script), f"Missing file: {start_script}"

    sshd_proc = None
    private_key = "/home/user/.ssh/id_rsa"
    backup_key = private_key + ".verifier-backup"
    try:
        subprocess.run(["bash", start_script], check=True, timeout=15)
        wait_for_port(8080)
        wait_for_port(2222)

        # Relaunch the configured daemon with an audit log so the endpoint must
        # cause a real, successful public-key authentication.
        subprocess.run(["pkill", "-x", "sshd"], check=False)
        time.sleep(0.4)
        try:
            os.remove("/app/sshd/sshd.pid")
        except FileNotFoundError:
            pass
        log_path = "/tmp/verifier_sshd.log"
        try:
            os.remove(log_path)
        except FileNotFoundError:
            pass
        sshd_proc = subprocess.Popen([
            "/usr/sbin/sshd", "-D", "-f", "/app/sshd/sshd_config",
            "-o", "LogLevel=VERBOSE", "-E", log_path
        ])
        wait_for_port(2222)

        # Prove that the generated key is accepted and find the usable account.
        candidates = ["user"]
        for entry in pwd.getpwall():
            if entry.pw_uid >= 1000 and entry.pw_name not in candidates:
                candidates.append(entry.pw_name)
        if "root" not in candidates:
            candidates.append("root")

        authenticated_user = None
        errors = []
        for username in candidates:
            client = paramiko.SSHClient()
            client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            try:
                client.connect(
                    "127.0.0.1", port=2222, username=username,
                    key_filename=private_key, look_for_keys=False,
                    allow_agent=False, timeout=3, auth_timeout=3
                )
                _, stdout, _ = client.exec_command("printf verifier-key-auth")
                assert stdout.read().decode() == "verifier-key-auth"
                authenticated_user = username
                client.close()
                break
            except Exception as exc:
                errors.append(f"{username}: {exc}")
                client.close()
        assert authenticated_user is not None, "Generated key could not authenticate to local SSHD: " + " | ".join(errors)

        # The effective daemon must not offer password authentication.
        password_client = paramiko.SSHClient()
        password_client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        with pytest.raises((paramiko.AuthenticationException, paramiko.SSHException)):
            password_client.connect(
                "127.0.0.1", port=2222, username=authenticated_user,
                password=secrets.token_urlsafe(24), look_for_keys=False,
                allow_agent=False, timeout=3, auth_timeout=3
            )
        password_client.close()

        time.sleep(0.3)
        log_offset = os.path.getsize(log_path)

        result = curl_trigger()
        assert result.returncode == 0, "Curl command failed to execute."
        assert '{"status": "success"}' in result.stdout or '{"status":"success"}' in result.stdout, f"Unexpected response from API: {result.stdout}"

        deadline = time.time() + 4
        trigger_log = ""
        while time.time() < deadline:
            with open(log_path, errors="replace") as f:
                f.seek(log_offset)
                trigger_log = f.read()
            if re.search(r"Accepted publickey for ", trigger_log):
                break
            time.sleep(0.1)
        assert re.search(r"Accepted publickey for ", trigger_log), "Calling /trigger did not perform a successful SSH public-key authentication."

        # A constant-success endpoint cannot pass: removing the required private
        # key must make the trigger fail until the key is restored.
        os.rename(private_key, backup_key)
        try:
            without_key = curl_trigger()
            assert without_key.returncode == 0
            assert not ('{"status": "success"}' in without_key.stdout or '{"status":"success"}' in without_key.stdout), \
                "/trigger reported success even though its SSH private key was unavailable."
        finally:
            os.rename(backup_key, private_key)
    finally:
        if os.path.exists(backup_key) and not os.path.exists(private_key):
            os.rename(backup_key, private_key)
        if sshd_proc is not None:
            sshd_proc.terminate()
            try:
                sshd_proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                sshd_proc.kill()
        subprocess.run(["pkill", "-f", "nginx"], stderr=subprocess.DEVNULL)
        subprocess.run(["pkill", "-f", "flask"], stderr=subprocess.DEVNULL)
        subprocess.run(["pkill", "-x", "sshd"], stderr=subprocess.DEVNULL)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
