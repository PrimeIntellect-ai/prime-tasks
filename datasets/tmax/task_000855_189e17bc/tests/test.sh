#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import os
import pwd
import re
import secrets
import stat
import subprocess
import tempfile


def test_ssh_configuration():
    ssh_dir = "/home/user/.ssh"
    priv_key = os.path.join(ssh_dir, "id_ed25519")
    pub_key = priv_key + ".pub"
    config_file = os.path.join(ssh_dir, "config")

    assert os.path.isfile(priv_key), f"SSH private key missing at {priv_key}"
    assert os.path.isfile(config_file), f"SSH config missing at {config_file}"
    assert os.path.isfile(pub_key), f"SSH public key missing at {pub_key}"

    for path in (ssh_dir, priv_key, pub_key, config_file):
        assert not os.path.islink(path), f"{path} must not be a symbolic link"

    assert stat.S_ISDIR(os.lstat(ssh_dir).st_mode), f"{ssh_dir} is not a directory"
    for path in (priv_key, pub_key, config_file):
        assert stat.S_ISREG(os.lstat(path).st_mode), f"{path} is not a regular file"

    user_uid = pwd.getpwnam("user").pw_uid
    for path in (ssh_dir, priv_key, pub_key, config_file):
        assert os.stat(path).st_uid == user_uid, f"{path} must be owned by user"

    assert stat.S_IMODE(os.stat(ssh_dir).st_mode) & 0o077 == 0, ".ssh has insecure group/other permissions"
    assert stat.S_IMODE(os.stat(priv_key).st_mode) & 0o077 == 0, "Private key has insecure group/other permissions"
    assert stat.S_IMODE(os.stat(config_file).st_mode) & 0o077 == 0, "SSH config has insecure group/other permissions"
    assert stat.S_IMODE(os.stat(pub_key).st_mode) & 0o022 == 0, "Public key is group/other writable"

    with open(config_file, "r") as f:
        config_content = f.read()

    assert re.search(r"Host\s+\*", config_content, re.IGNORECASE), "SSH config missing 'Host *'"
    assert re.search(r"PasswordAuthentication\s+no", config_content, re.IGNORECASE), "SSH config missing 'PasswordAuthentication no'"

    derived = subprocess.run(
        ["ssh-keygen", "-y", "-P", "", "-f", priv_key],
        capture_output=True, text=True, timeout=10
    )
    assert derived.returncode == 0, "Private key is invalid, encrypted, or not readable by ssh-keygen"

    with open(pub_key, "r") as f:
        public_parts = f.read().strip().split()
    derived_parts = derived.stdout.strip().split()
    assert len(public_parts) >= 2, "Public key is malformed"
    assert len(derived_parts) >= 2, "Could not derive a public key from the private key"
    assert public_parts[0] == "ssh-ed25519", "Keypair is not ED25519"
    assert derived_parts[0:2] == public_parts[0:2], "Public key does not match the private key"

    config_check = subprocess.run(
        ["ssh", "-G", "-F", config_file, "verification.invalid"],
        capture_output=True, text=True, timeout=10
    )
    assert config_check.returncode == 0, "SSH config is not valid"
    effective = {}
    for line in config_check.stdout.splitlines():
        parts = line.split(None, 1)
        if len(parts) == 2:
            effective[parts[0].lower()] = parts[1].strip().lower()
    assert effective.get("passwordauthentication") == "no", "Password authentication is not effectively disabled for all hosts"


def test_clean_hashes():
    hash_file = "/home/user/clean_hashes.txt"
    assert os.path.isfile(hash_file), f"Missing {hash_file}"

    clean_dir = "/app/corpus/clean"
    expected_hashes = {}
    for filename in os.listdir(clean_dir):
        filepath = os.path.join(clean_dir, filename)
        if os.path.isfile(filepath):
            with open(filepath, "rb") as f:
                expected_hashes[filepath] = hashlib.sha256(f.read()).hexdigest()

    with open(hash_file, "r") as f:
        lines = f.readlines()

    parsed_hashes = {}
    for line in lines:
        parts = line.strip().split(None, 1)
        if len(parts) == 2:
            h, p = parts
            p = p.lstrip(" *")
            parsed_hashes[p] = h

    for filepath, expected_hash in expected_hashes.items():
        assert filepath in parsed_hashes or os.path.basename(filepath) in parsed_hashes, f"Missing hash for {filepath} in {hash_file}"
        actual_hash = parsed_hashes.get(filepath) or parsed_hashes.get(os.path.basename(filepath))
        assert actual_hash == expected_hash, f"Incorrect hash for {filepath}"


def reference_redact(text, malicious_domain):
    key_pattern = re.compile(
        r"-----BEGIN (?P<label>(?:OPENSSH|RSA|DSA|EC) PRIVATE KEY)-----.*?"
        r"-----END (?P=label)-----",
        re.DOTALL,
    )
    text = key_pattern.sub("[REDACTED_KEY]", text)
    url_pattern = re.compile(
        r"(?<!\S)https?://\S*" + re.escape(malicious_domain) + r"\S*"
    )
    return url_pattern.sub("[REDACTED_URL]", text)


def run_redactor(script_path, filepath):
    return subprocess.run(
        [script_path, filepath], capture_output=True, text=True, timeout=10
    )


def test_redactor_script():
    script_path = "/home/user/redactor.py"
    assert os.path.isfile(script_path), f"Missing redactor script at {script_path}"
    assert stat.S_ISREG(os.lstat(script_path).st_mode), f"{script_path} is not a regular file"

    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {script_path} is not executable"

    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"
    malicious_domain = "malicious-redirect-host.local"

    clean_files = [f for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [f for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]

    clean_failures = []
    for filename in clean_files:
        filepath = os.path.join(clean_dir, filename)
        with open(filepath, "r") as f:
            original_content = f.read()

        result = run_redactor(script_path, filepath)
        if result.returncode != 0 or result.stdout != original_content:
            clean_failures.append(filename)

    evil_failures = []
    for filename in evil_files:
        filepath = os.path.join(evil_dir, filename)
        with open(filepath, "r") as f:
            original_content = f.read()
        result = run_redactor(script_path, filepath)

        if result.returncode != 0:
            evil_failures.append(filename)
            continue

        output = result.stdout

        # Preserve the original malicious-content assertions.
        if malicious_domain in output:
            evil_failures.append(filename)
            continue
        if "PRIVATE KEY-----" in output:
            evil_failures.append(filename)
            continue

        # Also require the exact specified transformation, including markers
        # and preservation of all non-sensitive text.
        if output != reference_redact(original_content, malicious_domain):
            evil_failures.append(filename)
            continue

    error_msg = []
    if evil_failures:
        error_msg.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed: {', '.join(evil_failures)}")
    if clean_failures:
        error_msg.append(f"{len(clean_failures)} of {len(clean_files)} clean modified: {', '.join(clean_failures)}")

    assert not error_msg, " | ".join(error_msg)

    # Exercise unseen inputs so a fixed-corpus dispatcher cannot pass.
    nonce = secrets.token_hex(12)
    payload = base64.b64encode(secrets.token_bytes(72)).decode("ascii")
    split_payload = "\n".join(payload[i:i+48] for i in range(0, len(payload), 48))

    dynamic_cases = [
        (
            "clean-unseen",
            f"Random note {nonce}\nSafe URL: https://example.invalid/{nonce}\n"
            f"Mentioned domain without a URL: {malicious_domain}\n"
            f"Not a URL word: prefixhttps://{malicious_domain}/{nonce}\n"
            "Public key: ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFakePublicData user@host\n",
        ),
        (
            "url-unseen",
            f"before {nonce}\nhttps://gateway.example/path?next=http://{malicious_domain}/collect/{nonce}?x=1 after\n",
        ),
        (
            "rsa-key-unseen",
            f"Start {nonce}\n-----BEGIN RSA PRIVATE KEY-----\n{split_payload}\n"
            f"-----END RSA PRIVATE KEY-----\nEnd {nonce}\n",
        ),
        (
            "combined-unseen",
            f"alpha {nonce}\nhttp://{malicious_domain}/x/{nonce}#fragment\n"
            f"middle\n-----BEGIN OPENSSH PRIVATE KEY-----\n{split_payload}\n"
            f"-----END OPENSSH PRIVATE KEY-----\n"
            f"https://safe.example/{nonce}\n"
            f"https://subdomain.example/redirect/{malicious_domain}/{nonce}\nomega\n",
        ),
        (
            "multiple-unseen",
            f"https://{malicious_domain}/{nonce} one\n"
            f"-----BEGIN EC PRIVATE KEY-----\n{split_payload}\n-----END EC PRIVATE KEY-----\n"
            f"between\n-----BEGIN DSA PRIVATE KEY-----\n{split_payload[::-1]}\n-----END DSA PRIVATE KEY-----\n",
        ),
    ]

    with tempfile.TemporaryDirectory(prefix="redactor-verification-") as td:
        for index, (name, content) in enumerate(dynamic_cases):
            filepath = os.path.join(td, f"{index}-{secrets.token_hex(5)}.txt")
            with open(filepath, "w") as f:
                f.write(content)
            result = run_redactor(script_path, filepath)
            assert result.returncode == 0, f"Redactor failed on dynamic case {name}: {result.stderr}"
            expected = reference_redact(content, malicious_domain)
            assert result.stdout == expected, f"Incorrect output for dynamic case {name}"

            if name != "clean-unseen":
                if malicious_domain in content:
                    assert "[REDACTED_URL]" in result.stdout, f"Missing URL marker for {name}"
                if "PRIVATE KEY-----" in content:
                    assert "[REDACTED_KEY]" in result.stdout, f"Missing key marker for {name}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
