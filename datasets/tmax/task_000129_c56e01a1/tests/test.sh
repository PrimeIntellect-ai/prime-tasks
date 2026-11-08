#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import hashlib
import base64
import subprocess

RECOVERED = "/home/user/recovered.dat"
EXPECTED_CONTENT = base64.b64decode("Q09ORklERU5USUFMX0ZPUkVOU0lDX0RBVEFfNzc4ODk5Cg==")


def test_recovered_dat_exists_and_correct():
    path = RECOVERED
    assert os.path.isfile(path), f"Missing file: {path}. Did you successfully run the compiled backdoor?"

    with open(path, "rb") as f:
        actual_content = f.read()

    assert actual_content == EXPECTED_CONTENT, f"The content of {path} does not match the expected decrypted evidence."


def test_evidence_hash_txt():
    path = "/home/user/evidence_hash.txt"
    assert os.path.isfile(path), f"Missing file: {path}"

    expected_hash = hashlib.sha256(EXPECTED_CONTENT).hexdigest()

    with open(path, "r") as f:
        actual_hash = f.read().strip()

    # In case they used `sha256sum recovered.dat > evidence_hash.txt`, it might contain the filename.
    # We take the first word.
    actual_hash = actual_hash.split()[0] if actual_hash else ""

    assert actual_hash == expected_hash, f"The hash in {path} is incorrect. Expected {expected_hash}, got {actual_hash}."


def _crafted_password():
    # Derive a printable 10-byte password with fixed endpoints and total byte sum 900.
    interior = [33] * 8
    remaining = 900 - ord('F') - ord('X') - sum(interior)
    for i in range(len(interior)):
        add = min(126 - interior[i], remaining)
        interior[i] += add
        remaining -= add
    assert remaining == 0
    password = 'F' + ''.join(chr(c) for c in interior) + 'X'
    assert len(password) == 10
    assert sum(ord(c) for c in password) == 900
    return password


def _candidate_executables():
    required_literals = (
        b"Evidence decrypted.",
        b"Invalid password.",
        b"Invalid length.",
        b"/home/user/evidence.enc",
        b"/home/user/recovered.dat",
    )
    candidates = []
    for root, dirs, files in os.walk("/home/user"):
        for name in files:
            path = os.path.join(root, name)
            try:
                if not os.path.isfile(path) or not os.access(path, os.X_OK):
                    continue
                with open(path, "rb") as f:
                    data = f.read()
                if not data.startswith(b"\x7fELF"):
                    continue
                if all(literal in data for literal in required_literals):
                    candidates.append(path)
            except OSError:
                continue
    return sorted(candidates)


def _run(binary, password):
    return subprocess.run(
        [binary, password],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
        check=False,
    )


def test_zz_compiled_backdoor_enforces_authentication_and_decrypts():
    candidates = _candidate_executables()
    assert candidates, "No executable ELF compiled from backdoor.c was found under /home/user"

    valid_password = _crafted_password()
    failures = []

    for binary in candidates:
        try:
            if os.path.exists(RECOVERED):
                os.remove(RECOVERED)
            short_result = _run(binary, "short")
            if os.path.exists(RECOVERED) or b"Invalid length." not in short_result.stdout:
                failures.append(f"{binary}: did not reject an invalid-length password")
                continue

            wrong_password = "A" * 10
            wrong_result = _run(binary, wrong_password)
            if os.path.exists(RECOVERED) or b"Invalid password." not in wrong_result.stdout:
                failures.append(f"{binary}: did not reject a length-10 password with the wrong sum")
                continue

            valid_result = _run(binary, valid_password)
            if b"Evidence decrypted." not in valid_result.stdout:
                failures.append(f"{binary}: did not accept the derived valid password")
                continue
            if not os.path.isfile(RECOVERED):
                failures.append(f"{binary}: accepted the password but did not create recovered.dat")
                continue
            with open(RECOVERED, "rb") as f:
                decrypted = f.read()
            if decrypted != EXPECTED_CONTENT:
                failures.append(f"{binary}: produced incorrect decrypted evidence")
                continue
            return
        except (OSError, subprocess.SubprocessError) as exc:
            failures.append(f"{binary}: {exc}")

    assert False, "No compiled backdoor passed authentication/decryption checks: " + "; ".join(failures)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
