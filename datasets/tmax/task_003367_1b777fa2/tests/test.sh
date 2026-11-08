#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_task.py
import base64
import hashlib
import ipaddress
import os
import re
import secrets
import stat
import subprocess

PROJECT = "/home/user/rotator"
CARGO_TOML = os.path.join(PROJECT, "Cargo.toml")
MAIN_RS = os.path.join(PROJECT, "src", "main.rs")
LOG = "/home/user/rotation.log"


def run_cargo(args, expect_success=True):
    cmd = ["cargo", "run", "--quiet", "--"] + args
    result = subprocess.run(
        cmd,
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
        env={**os.environ, "CARGO_TERM_COLOR": "never"},
    )
    if expect_success:
        assert result.returncode == 0, (
            f"{' '.join(cmd)} failed with exit code {result.returncode}.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
    else:
        assert result.returncode != 0, (
            f"Program accepted {len(args)} arguments, but it must accept exactly three."
        )
    return result


def expected_log(compromised, attacker_ip, new_password):
    digest = hashlib.sha256(new_password.encode("utf-8")).hexdigest()
    return (
        f"COMPROMISED_PASS: {compromised}\n"
        f"ATTACKER_IP: {attacker_ip}\n"
        f"NEW_PASS_HASH: {digest}\n"
    ).encode("utf-8")


def derive_incident_values():
    with open("/home/user/web_server.log", "r", encoding="utf-8") as f:
        web_log = f.read()
    match = re.search(r"file=((?:\.\./)+[^\s]+)", web_log)
    assert match, "No path traversal request was found in web_server.log"
    relative = re.sub(r"^(?:\.\./)+", "", match.group(1))
    credential_path = os.path.join("/", relative)
    assert os.path.isfile(credential_path), f"Discovered credential file is missing: {credential_path}"

    with open(credential_path, "r", encoding="utf-8") as f:
        stored_hash = f.read().strip().split(":", 1)[1]
    with open("/home/user/wordlist.txt", "r", encoding="utf-8") as f:
        words = [line.rstrip("\n") for line in f]
    cracked = next(
        (word for word in words if hashlib.sha256(word.encode("utf-8")).hexdigest() == stored_hash),
        None,
    )
    assert cracked is not None, "The credential hash could not be cracked with the supplied wordlist"

    with open("/home/user/payload.enc", "rb") as f:
        encoded = f.read().strip()
    attacker_ip = bytes(byte ^ 0x5A for byte in base64.b64decode(encoded)).decode("ascii")
    ipaddress.ip_address(attacker_ip)
    return cracked, attacker_ip


# Preserve the original verifier's assertions.
def test_rotation_log_exists():
    path = "/home/user/rotation.log"
    assert os.path.isfile(path), f"Expected output file {path} is missing. Did the Rust program run and create it?"


def test_rotation_log_contents():
    path = "/home/user/rotation.log"
    assert os.path.isfile(path), f"Cannot check contents, {path} is missing."
    with open(path, "r") as f:
        content = f.read()
    expected_compromised_pass = "supersecret99"
    expected_attacker_ip = "192.168.133.7"
    new_password = "SecureRotation2024!"
    expected_new_pass_hash = hashlib.sha256(new_password.encode("utf-8")).hexdigest()
    expected_line1 = f"COMPROMISED_PASS: {expected_compromised_pass}"
    expected_line2 = f"ATTACKER_IP: {expected_attacker_ip}"
    expected_line3 = f"NEW_PASS_HASH: {expected_new_pass_hash}"
    assert expected_line1 in content, f"Log file does not contain the correct compromised password line. Expected: '{expected_line1}'"
    assert expected_line2 in content, f"Log file does not contain the correct attacker IP line. Expected: '{expected_line2}'"
    assert expected_line3 in content, f"Log file does not contain the correct new password hash line. Expected: '{expected_line3}'"


def test_rust_project_exists():
    assert os.path.isfile(CARGO_TOML), f"Rust project not found at /home/user/rotator. {CARGO_TOML} is missing."


def main():
    test_rust_project_exists()
    assert os.path.isfile(MAIN_RS), f"Expected Rust application source is missing: {MAIN_RS}"
    assert stat.S_ISREG(os.stat(MAIN_RS).st_mode), f"Rust application source is not a regular file: {MAIN_RS}"

    # Remove any prewritten answer and exercise the submitted Rust application
    # with unpredictable valid inputs.
    if os.path.lexists(LOG):
        os.remove(LOG)
    token = secrets.token_hex(12)
    trial_compromised = "trialpass_" + token
    trial_ip = f"198.51.100.{secrets.randbelow(253) + 1}"
    trial_new_password = "Rotate_" + secrets.token_urlsafe(18) + "!"
    run_cargo([trial_compromised, trial_ip, trial_new_password])
    assert os.path.isfile(LOG), "cargo run succeeded but did not create /home/user/rotation.log"
    with open(LOG, "rb") as f:
        actual = f.read()
    assert actual == expected_log(trial_compromised, trial_ip, trial_new_password), (
        "The Rust program did not write rotation.log in the exact required format for test inputs"
    )

    # Enforce the requirement that exactly three application arguments are accepted.
    run_cargo([], expect_success=False)
    run_cargo(["one", "two"], expect_success=False)
    run_cargo(["one", "two", "three", "four"], expect_success=False)

    # Derive the incident answers from the supplied artifacts and perform the
    # required final invocation.
    cracked, attacker_ip = derive_incident_values()
    new_password = "SecureRotation2024!"
    if os.path.lexists(LOG):
        os.remove(LOG)
    run_cargo([cracked, attacker_ip, new_password])
    assert os.path.isfile(LOG), "The required cargo run did not generate /home/user/rotation.log"
    with open(LOG, "rb") as f:
        final_content = f.read()
    assert final_content == expected_log(cracked, attacker_ip, new_password), (
        "Final rotation.log does not exactly match the required three-line format"
    )

    test_rotation_log_exists()
    test_rotation_log_contents()


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
