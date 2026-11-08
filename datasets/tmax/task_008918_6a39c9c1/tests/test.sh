#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import secrets
import stat
import subprocess
import tempfile

CLEAN_LOG_PATH = "/home/user/clean_traffic.log"
SHA256_PATH = "/home/user/clean_traffic.sha256"
BLOCK_SCRIPT_PATH = "/home/user/block_c2.sh"
TRAFFIC_LOG_PATH = "/home/user/traffic.log"


def test_clean_traffic_log_content():
    assert os.path.isfile(CLEAN_LOG_PATH), f"File {CLEAN_LOG_PATH} is missing."

    expected_lines = [
        "[2023-10-25 10:00:01] [10.0.0.5] [192.168.1.50] USER:john SSN:XXX-XX-XXXX",
        "[2023-10-25 10:00:02] [192.168.1.100] [10.0.0.5] DECRYPTED: C2: 10.9.8.7",
        "[2023-10-25 10:00:03] [10.0.0.6] [192.168.1.51] USER:alice SSN:XXX-XX-XXXX"
    ]

    with open(CLEAN_LOG_PATH, "r") as f:
        content = f.read()

    actual_lines = [line for line in content.splitlines() if line.strip()]
    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in {CLEAN_LOG_PATH}, but found {len(actual_lines)}."

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual.strip() == expected, f"Line {i+1} in {CLEAN_LOG_PATH} does not match expected output.\nExpected: {expected}\nActual: {actual.strip()}"


def test_clean_traffic_sha256():
    assert os.path.isfile(SHA256_PATH), f"File {SHA256_PATH} is missing."
    assert os.path.isfile(CLEAN_LOG_PATH), f"Cannot compute hash, {CLEAN_LOG_PATH} is missing."

    with open(CLEAN_LOG_PATH, "rb") as f:
        actual_hash = hashlib.sha256(f.read()).hexdigest()

    with open(SHA256_PATH, "r") as f:
        stored_hash_content = f.read().strip()

    assert actual_hash in stored_hash_content, f"The hash in {SHA256_PATH} does not match the actual SHA-256 hash of {CLEAN_LOG_PATH}.\nExpected to find: {actual_hash}"


def test_block_c2_script():
    assert os.path.isfile(BLOCK_SCRIPT_PATH), f"File {BLOCK_SCRIPT_PATH} is missing."
    assert os.access(BLOCK_SCRIPT_PATH, os.X_OK), f"File {BLOCK_SCRIPT_PATH} is not marked as executable."

    with open(BLOCK_SCRIPT_PATH, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) >= 2, f"{BLOCK_SCRIPT_PATH} does not contain enough lines."
    assert lines[0] == "#!/bin/bash", f"First line of {BLOCK_SCRIPT_PATH} must be '#!/bin/bash'."

    expected_iptables = "iptables -A OUTPUT -d 10.9.8.7 -j DROP"
    has_iptables = any(expected_iptables in line for line in lines[1:])
    assert has_iptables, f"Could not find the exact iptables command in {BLOCK_SCRIPT_PATH}.\nExpected: {expected_iptables}"

    assert len(lines) == 2, f"{BLOCK_SCRIPT_PATH} must contain only the shebang and exactly one iptables command."
    assert lines[1] == expected_iptables, f"The sole command in {BLOCK_SCRIPT_PATH} must be exactly: {expected_iptables}"


def test_c_program_compiles_and_processes_fresh_input():
    sources = []
    for root, dirs, files in os.walk("/home/user"):
        for name in files:
            path = os.path.join(root, name)
            try:
                mode = os.lstat(path).st_mode
            except OSError:
                continue
            if name.lower().endswith(".c") and stat.S_ISREG(mode) and not os.path.islink(path):
                sources.append(path)

    assert sources, "No regular C source file was written under /home/user."

    protected = [TRAFFIC_LOG_PATH, CLEAN_LOG_PATH, SHA256_PATH, BLOCK_SCRIPT_PATH]
    snapshots = {}
    for path in protected:
        if os.path.exists(path):
            with open(path, "rb") as f:
                snapshots[path] = (f.read(), stat.S_IMODE(os.stat(path).st_mode))
        else:
            snapshots[path] = None

    ssn1 = str(secrets.randbelow(900000000) + 100000000)
    ssn2 = str(secrets.randbelow(900000000) + 100000000)
    c2_ip = ".".join(str(secrets.randbelow(200) + 20) for _ in range(4))
    decrypted = f"C2: {c2_ip}"
    encrypted = bytes(b ^ 0x5A for b in decrypted.encode("ascii")).hex().upper()

    input_text = (
        f"[2026-04-11 08:17:03] [10.44.7.9] [172.20.3.8] USER:delta SSN:{ssn1}\n"
        f"[2026-04-11 08:17:04] [192.168.1.100] [10.44.7.9] {encrypted}\n"
        f"[2026-04-11 08:17:05] [10.44.7.10] [172.20.3.9] USER:echo SSN:{ssn2}\n"
    )
    expected = (
        "[2026-04-11 08:17:03] [10.44.7.9] [172.20.3.8] USER:delta SSN:XXX-XX-XXXX\n"
        f"[2026-04-11 08:17:04] [192.168.1.100] [10.44.7.9] DECRYPTED: C2: {c2_ip}\n"
        "[2026-04-11 08:17:05] [10.44.7.10] [172.20.3.9] USER:echo SSN:XXX-XX-XXXX\n"
    ).encode("utf-8")

    errors = []
    try:
        with tempfile.TemporaryDirectory() as td:
            for index, source in enumerate(sources):
                binary = os.path.join(td, f"candidate_{index}")
                compiled = subprocess.run(
                    ["gcc", "-std=c11", "-O2", source, "-o", binary],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=20,
                )
                if compiled.returncode != 0:
                    errors.append(f"{source}: compilation failed")
                    continue

                with open(TRAFFIC_LOG_PATH, "w", encoding="utf-8") as f:
                    f.write(input_text)
                try:
                    os.remove(CLEAN_LOG_PATH)
                except FileNotFoundError:
                    pass

                try:
                    ran = subprocess.run(
                        [binary],
                        cwd="/home/user",
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                        timeout=10,
                    )
                except subprocess.TimeoutExpired:
                    errors.append(f"{source}: executable timed out")
                    continue

                if ran.returncode != 0:
                    errors.append(f"{source}: executable returned {ran.returncode}")
                    continue
                if not os.path.isfile(CLEAN_LOG_PATH):
                    errors.append(f"{source}: executable did not create {CLEAN_LOG_PATH}")
                    continue
                with open(CLEAN_LOG_PATH, "rb") as f:
                    actual = f.read()
                if actual == expected:
                    return
                errors.append(f"{source}: output was incorrect for fresh input")

        assert False, "No submitted C program compiled and correctly processed fresh input. " + "; ".join(errors)
    finally:
        for path, snapshot in snapshots.items():
            if snapshot is None:
                try:
                    os.remove(path)
                except FileNotFoundError:
                    pass
            else:
                data, mode = snapshot
                with open(path, "wb") as f:
                    f.write(data)
                os.chmod(path, mode)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
