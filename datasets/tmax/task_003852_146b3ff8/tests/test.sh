#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import secrets
import shutil
import stat
import subprocess

HOME = "/home/user"
SOURCE = f"{HOME}/payload.cpp"
PAYLOAD = f"{HOME}/payload"
LOG = f"{HOME}/payload_config.log"
FIREWALL = f"{HOME}/firewall_rules.txt"
ENV_FILE = f"{HOME}/target_environment.txt"
PIN_HASH = f"{HOME}/pin_hash.txt"
STAGE2 = f"{HOME}/stage2.enc"


def replace_file(path, data, mode=0o644):
    if os.path.lexists(path):
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)
    with open(path, "wb") as f:
        f.write(data)
    os.chmod(path, mode)


def configure_case(port, env_content, pin, plaintext):
    firewall = (
        "iptables -P INPUT DROP\n"
        "iptables -P OUTPUT DROP\n"
        "iptables -A OUTPUT -p tcp --dport 80 -j DROP\n"
        "iptables -A OUTPUT -p tcp --dport 443 -j DROP\n"
        f"iptables -A OUTPUT -p udp --dport {port} -j ACCEPT\n"
        "iptables -A OUTPUT -p udp --dport 53 -j DROP\n"
    ).encode()
    replace_file(FIREWALL, firewall)
    replace_file(ENV_FILE, env_content)
    replace_file(PIN_HASH, hashlib.md5(pin.encode()).hexdigest().encode() + b"\n")

    if os.path.lexists(STAGE2):
        if os.path.isdir(STAGE2) and not os.path.islink(STAGE2):
            shutil.rmtree(STAGE2)
        else:
            os.unlink(STAGE2)
    subprocess.run(
        [
            "openssl", "enc", "-aes-256-cbc", "-md", "md5", "-pbkdf2",
            "-iter", "10000", "-pass", f"pass:{pin}", "-out", STAGE2,
        ],
        input=plaintext.encode() + b"\n",
        check=True,
        timeout=30,
    )
    os.chmod(STAGE2, 0o644)


def execute_and_parse():
    if os.path.lexists(LOG):
        if os.path.isdir(LOG) and not os.path.islink(LOG):
            shutil.rmtree(LOG)
        else:
            os.unlink(LOG)

    subprocess.run(
        ["runuser", "-u", "user", "--", PAYLOAD],
        cwd=HOME,
        check=True,
        timeout=60,
    )

    assert os.path.isfile(LOG), f"Log file {LOG} was not created. The payload must execute and generate this file."
    with open(LOG, "r", encoding="utf-8") as f:
        lines = [line.rstrip("\n") for line in f]

    assert len(lines) == 4, "The payload log must contain exactly four lines."
    log_data = {}
    for line in lines:
        assert "=" in line, f"Malformed payload log line: {line!r}"
        key, val = line.split("=", 1)
        assert key not in log_data, f"Duplicate key in payload log: {key}"
        log_data[key] = val
    assert set(log_data) == {"EGRESS_PORT", "ENV_HASH", "PIN", "STAGE2"}, "The payload log must use the exact required keys."
    return log_data


def test_payload_source_binary_and_dynamic_behavior():
    assert os.path.isfile(SOURCE) and not os.path.islink(SOURCE), f"C++ source file {SOURCE} is missing or is not a regular file."
    assert os.path.getsize(SOURCE) > 0, f"C++ source file {SOURCE} is empty."

    assert os.path.isfile(PAYLOAD) and not os.path.islink(PAYLOAD), f"Compiled payload {PAYLOAD} is missing or is not a regular file."
    assert os.stat(PAYLOAD).st_mode & stat.S_IXUSR, f"Compiled payload {PAYLOAD} is not executable."
    with open(PAYLOAD, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Compiled payload {PAYLOAD} is not an ELF executable."

    rebuilt = f"/tmp/payload-rebuilt-{secrets.token_hex(8)}"
    try:
        subprocess.run(
            ["g++", "-std=c++17", SOURCE, "-o", rebuilt, "-lssl", "-lcrypto"],
            check=True,
            timeout=60,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        os.chmod(rebuilt, 0o755)
        os.replace(rebuilt, PAYLOAD)

        # Preserve and exercise all assertions from the original fixed case.
        original_env = b"PRODUCTION_SERVER_V2\n"
        configure_case(1337, original_env, "7391", "REVERSE_SHELL_ACTIVATED")
        log_data = execute_and_parse()

        assert os.path.exists(LOG), f"Log file {LOG} was not created. The payload must execute and generate this file."
        assert os.path.exists(ENV_FILE), f"Environment file {ENV_FILE} is missing, cannot compute expected hash."
        expected_hash = hashlib.sha256(original_env).hexdigest()

        assert "EGRESS_PORT" in log_data, "EGRESS_PORT key is missing from the payload log."
        assert log_data["EGRESS_PORT"] == "1337", f"Expected EGRESS_PORT to be 1337, but got {log_data['EGRESS_PORT']}."
        assert "ENV_HASH" in log_data, "ENV_HASH key is missing from the payload log."
        assert log_data["ENV_HASH"] == expected_hash, f"Expected ENV_HASH to be {expected_hash}, but got {log_data['ENV_HASH']}."
        assert "PIN" in log_data, "PIN key is missing from the payload log."
        assert log_data["PIN"] == "7391", f"Expected cracked PIN to be 7391, but got {log_data['PIN']}."
        assert "STAGE2" in log_data, "STAGE2 key is missing from the payload log."
        assert log_data["STAGE2"] == "REVERSE_SHELL_ACTIVATED", f"Expected STAGE2 decrypted text to be 'REVERSE_SHELL_ACTIVATED', but got '{log_data['STAGE2']}'."

        # A fresh unpredictable case prevents passing by writing the fixed answers.
        port = secrets.randbelow(50000) + 10000
        while port in (1337, 53):
            port = secrets.randbelow(50000) + 10000
        pin = f"{secrets.randbelow(10000):04d}"
        while pin == "7391":
            pin = f"{secrets.randbelow(10000):04d}"
        env_content = f"DYNAMIC_ENVIRONMENT_{secrets.token_hex(16)}\n".encode()
        plaintext = f"DYNAMIC_STAGE2_{secrets.token_hex(16)}"

        configure_case(port, env_content, pin, plaintext)
        dynamic_log = execute_and_parse()
        assert dynamic_log["EGRESS_PORT"] == str(port), "The payload did not dynamically parse the allowed outbound UDP port."
        assert dynamic_log["ENV_HASH"] == hashlib.sha256(env_content).hexdigest(), "The payload did not hash the current target environment file."
        assert dynamic_log["PIN"] == pin, "The payload did not recover the current four-digit PIN from its MD5 hash."
        assert dynamic_log["STAGE2"] == plaintext, "The payload did not decrypt the current stage2 ciphertext with the recovered PIN."
    finally:
        if os.path.exists(rebuilt):
            os.unlink(rebuilt)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
