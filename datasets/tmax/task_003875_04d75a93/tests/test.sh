#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import pathlib
import random
import re
import secrets
import string
import subprocess


def test_audit_report_csv_content():
    csv_path = "/home/user/audit_report.csv"
    assert os.path.isfile(csv_path), f"File missing: {csv_path}"

    with open(csv_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "alice,d09a3410,pass",
        "bob,1e3f8a00,carl",
        "charlie,8bf8f47d,luke",
        "diana,717c1407,zack",
        "eve,c9842a27,root"
    ]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} rows in {csv_path}, found {len(lines)}"

    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Row {i+1} mismatch: expected '{expected}', got '{actual}'"


def test_audit_report_sha256_validity():
    csv_path = "/home/user/audit_report.csv"
    sha_path = "/home/user/audit_report.sha256"

    assert os.path.isfile(csv_path), f"File missing: {csv_path}"
    assert os.path.isfile(sha_path), f"File missing: {sha_path}"

    with open(csv_path, "rb") as f:
        csv_bytes = f.read()

    actual_sha256 = hashlib.sha256(csv_bytes).hexdigest()

    with open(sha_path, "r") as f:
        sha_content = f.read().strip()

    assert actual_sha256 in sha_content, f"The computed SHA-256 ({actual_sha256}) was not found in {sha_path}"


def fnv1a(password):
    value = 0x811c9dc5
    for byte in password.encode("ascii"):
        value ^= byte
        value = (value * 0x01000193) & 0xffffffff
    return value


def test_cracker_compiles_runs_and_recovers_unseen_accounts():
    home = pathlib.Path("/home/user")
    source = home / "cracker.cpp"
    accounts_path = home / "compromised_accounts.txt"
    csv_path = home / "audit_report.csv"
    sha_path = home / "audit_report.sha256"
    executable = pathlib.Path(f"/tmp/cracker_verify_{secrets.token_hex(8)}")

    assert source.is_file(), f"File missing: {source}"

    compile_result = subprocess.run(
        ["g++", "-std=c++17", "-O2", str(source), "-o", str(executable)],
        cwd=str(home), text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=60
    )
    assert compile_result.returncode == 0, "cracker.cpp did not compile:\n" + compile_result.stderr
    assert executable.is_file(), "Compilation did not produce an executable"

    originals = {
        accounts_path: accounts_path.read_bytes(),
        csv_path: csv_path.read_bytes(),
        sha_path: sha_path.read_bytes(),
    }

    alphabet = string.ascii_lowercase
    generated = []
    used_hashes = set()
    while len(generated) < 7:
        password = "".join(secrets.choice(alphabet) for _ in range(4))
        hash_value = fnv1a(password)
        if hash_value in used_hashes:
            continue
        used_hashes.add(hash_value)
        username = f"acct_{secrets.token_hex(6)}_{len(generated)}"
        generated.append((username, f"{hash_value:08x}"))

    shuffled = generated[:]
    random.SystemRandom().shuffle(shuffled)

    try:
        accounts_path.write_text("".join(f"{user}:{hash_hex}\n" for user, hash_hex in shuffled))
        csv_path.unlink(missing_ok=True)
        sha_path.unlink(missing_ok=True)

        run_result = subprocess.run(
            [str(executable)], cwd=str(home), text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120
        )
        assert run_result.returncode == 0, (
            f"Compiled cracker exited with status {run_result.returncode}.\n"
            f"stdout:\n{run_result.stdout}\nstderr:\n{run_result.stderr}"
        )
        assert csv_path.is_file(), "The executed cracker did not create audit_report.csv"
        assert sha_path.is_file(), "The executed cracker did not create audit_report.sha256"

        lines = [line.strip() for line in csv_path.read_text().splitlines() if line.strip()]
        assert len(lines) == len(generated), f"Expected {len(generated)} dynamically generated rows, found {len(lines)}"

        expected_by_user = dict(generated)
        seen_users = []
        for line in lines:
            fields = line.split(",")
            assert len(fields) == 3, f"Invalid CSV row: {line!r}"
            username, hash_hex, recovered = fields
            assert username in expected_by_user, f"Unexpected username in report: {username!r}"
            assert username not in seen_users, f"Duplicate username in report: {username!r}"
            assert hash_hex == expected_by_user[username], f"Incorrect hash for {username}"
            assert re.fullmatch(r"[a-z]{4}", recovered), f"Invalid recovered password for {username}: {recovered!r}"
            assert f"{fnv1a(recovered):08x}" == hash_hex, f"Recovered password for {username} does not match its hash"
            seen_users.append(username)

        assert seen_users == sorted(expected_by_user), "Dynamic report rows are not sorted alphabetically by username"

        actual_sha256 = hashlib.sha256(csv_path.read_bytes()).hexdigest()
        sha_content = sha_path.read_text().strip()
        assert actual_sha256 in sha_content, "Dynamic report checksum is missing or incorrect"
    finally:
        for path, content in originals.items():
            path.write_bytes(content)
        executable.unlink(missing_ok=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
