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


def test_extracted_password():
    path = "/home/user/extracted_password.txt"
    assert os.path.exists(path), f"File {path} is missing."

    with open(path, "r") as f:
        content = f.read()

    expected_password = "B@ckd00r_99!"
    assert content == expected_password, f"Expected extracted password to be '{expected_password}', but got '{content}'."


def test_compromised_ips():
    ips_path = "/home/user/compromised_ips.txt"
    traffic_path = "/home/user/traffic.bin"

    assert os.path.exists(ips_path), f"File {ips_path} is missing."
    assert os.path.exists(traffic_path), f"File {traffic_path} is missing."

    expected_ips = []
    with open(traffic_path, "rb") as f:
        while True:
            record = f.read(21)
            if not record or len(record) < 21:
                break
            ip_bytes = record[0:4]
            pwd_bytes = record[4:20]
            success = record[20]

            pwd_str = pwd_bytes.split(b'\x00')[0].decode('ascii', errors='ignore')
            if pwd_str == "B@ckd00r_99!" and success == 1:
                ip_str = ".".join(str(b) for b in ip_bytes)
                expected_ips.append(ip_str)

    with open(ips_path, "r") as f:
        actual_ips = [line.strip() for line in f.readlines() if line.strip()]

    assert set(actual_ips) == set(expected_ips), f"Expected IPs {expected_ips}, but got {actual_ips}."


def test_rotated_hash():
    hash_path = "/home/user/rotated_hash.txt"
    new_pass_path = "/home/user/new_password.txt"

    assert os.path.exists(hash_path), f"File {hash_path} is missing."
    assert os.path.exists(new_pass_path), f"File {new_pass_path} is missing."

    with open(new_pass_path, "r") as f:
        new_password = f.read()

    expected_hash = hashlib.sha256(new_password.encode('utf-8')).hexdigest()

    with open(hash_path, "r") as f:
        actual_hash = f.read()

    assert actual_hash == expected_hash, f"Expected hash '{expected_hash}', but got '{actual_hash}'."


def _assert_regular_file(path):
    assert os.path.exists(path), f"File {path} is missing."
    mode = os.lstat(path).st_mode
    assert stat.S_ISREG(mode), f"{path} must be a regular file."


def _record(ip, password, success):
    ip_bytes = bytes(int(part) for part in ip.split('.'))
    password_bytes = password.encode('ascii')
    assert len(password_bytes) <= 16
    return ip_bytes + password_bytes.ljust(16, b'\x00') + bytes([success])


def _random_ip():
    return ".".join(str(secrets.randbelow(254) + 1) for _ in range(4))


def test_detect_usage_source_compiles_and_processes_runtime_traffic():
    source = "/home/user/detect_usage.cpp"
    traffic_path = "/home/user/traffic.bin"
    output_path = "/home/user/compromised_ips.txt"
    _assert_regular_file(source)

    fd, binary = tempfile.mkstemp(prefix="detect_usage_", dir="/tmp")
    os.close(fd)
    os.unlink(binary)

    subprocess.run(
        ["g++", "-std=c++17", source, "-o", binary],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )

    good_ip_1 = _random_ip()
    good_ip_2 = _random_ip()
    failed_ip = _random_ip()
    wrong_ip = _random_ip()
    records = [
        _record(wrong_ip, "not_the_backdoor", 1),
        _record(good_ip_1, "B@ckd00r_99!", 1),
        _record(failed_ip, "B@ckd00r_99!", 0),
        _record(good_ip_2, "B@ckd00r_99!", 1),
    ]

    original_traffic = open(traffic_path, "rb").read()
    original_output = open(output_path, "rb").read()
    try:
        with open(traffic_path, "wb") as f:
            f.write(b"".join(records))
        if os.path.exists(output_path):
            os.remove(output_path)

        subprocess.run(
            [binary],
            check=True,
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )

        assert os.path.exists(output_path), "detect_usage.cpp did not create compromised_ips.txt."
        with open(output_path, "r") as f:
            actual = [line.strip() for line in f if line.strip()]
        expected = [good_ip_1, good_ip_2]
        assert set(actual) == set(expected), f"Runtime traffic expected IPs {expected}, but got {actual}."
    finally:
        with open(traffic_path, "wb") as f:
            f.write(original_traffic)
        with open(output_path, "wb") as f:
            f.write(original_output)
        if os.path.exists(binary):
            os.remove(binary)


def test_rotate_source_and_compiled_program_hash_runtime_passwords():
    source = "/home/user/rotate.cpp"
    executable = "/home/user/rotate"
    password_path = "/home/user/new_password.txt"
    output_path = "/home/user/rotated_hash.txt"

    _assert_regular_file(source)
    _assert_regular_file(executable)
    assert os.access(executable, os.X_OK), f"{executable} is not executable."
    with open(executable, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{executable} is not an ELF executable."

    fd, rebuilt = tempfile.mkstemp(prefix="rotate_rebuilt_", dir="/tmp")
    os.close(fd)
    os.unlink(rebuilt)
    subprocess.run(
        ["g++", "-std=c++17", source, "-o", rebuilt, "-lcrypto"],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )

    original_password = open(password_path, "rb").read()
    original_output = open(output_path, "rb").read()

    def exercise(program, password):
        with open(password_path, "w") as f:
            f.write(password)
        if os.path.exists(output_path):
            os.remove(output_path)
        subprocess.run(
            [program],
            check=True,
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
        assert os.path.exists(output_path), f"{program} did not create rotated_hash.txt."
        with open(output_path, "r") as f:
            actual = f.read()
        expected = hashlib.sha256(password.encode("utf-8")).hexdigest()
        assert actual == expected, f"{program} produced '{actual}', expected '{expected}'."

    try:
        exercise(executable, "RuntimePass-" + secrets.token_hex(12))
        exercise(rebuilt, "SourcePass-" + secrets.token_hex(12))
    finally:
        with open(password_path, "wb") as f:
            f.write(original_password)
        with open(output_path, "wb") as f:
            f.write(original_output)
        if os.path.exists(rebuilt):
            os.remove(rebuilt)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
