#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import signal
import subprocess
import time
import timeit

import pytest
from passlib.hash import md5_crypt

AUDIT_PATH = "/home/user/audit.py"
HASHES_PATH = "/home/user/legacy_hashes.txt"
WORDLIST_PATH = "/home/user/wordlist.txt"
JSON_PATH = "/home/user/cracked.json"

ORIGINAL_HASHES = [
    "$1$rK3a9V1p$M8a5.h4g.K3p9v7Z4g2H10",
    "$1$aB2cD3eF$x8Y9z0A1b2C3d4E5f6G7h.",
]


def _descendants(root_pid):
    descendants = {root_pid}
    changed = True
    while changed:
        changed = False
        try:
            pids = [int(name) for name in os.listdir("/proc") if name.isdigit()]
        except FileNotFoundError:
            return descendants
        for pid in pids:
            if pid in descendants:
                continue
            try:
                with open(f"/proc/{pid}/status", "r") as f:
                    status = f.read().splitlines()
                ppid = int(next(line.split()[1] for line in status if line.startswith("PPid:")))
            except (OSError, StopIteration, ValueError):
                continue
            if ppid in descendants:
                descendants.add(pid)
                changed = True
    return descendants


def _run_audit_without_password_argv(passwords, timeout=30):
    proc = subprocess.Popen(
        ["python3", AUDIT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    leaked = []
    deadline = time.monotonic() + timeout

    try:
        while proc.poll() is None:
            if time.monotonic() > deadline:
                os.killpg(proc.pid, signal.SIGKILL)
                pytest.fail("audit.py did not finish within the timeout")

            for pid in _descendants(proc.pid):
                try:
                    with open(f"/proc/{pid}/cmdline", "rb") as f:
                        cmdline = f.read()
                except OSError:
                    continue
                for password in passwords:
                    if password and password.encode() in cmdline:
                        leaked.append((pid, password, cmdline.replace(b"\0", b" ")))
            time.sleep(0.0005)

        stdout, stderr = proc.communicate()
    finally:
        if proc.poll() is None:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.wait()

    assert proc.returncode == 0, (
        f"audit.py exited with status {proc.returncode}.\n"
        f"stdout:\n{stdout}\nstderr:\n{stderr}"
    )
    assert not leaked, f"Passwords were exposed in process command lines: {leaked!r}"


def _load_and_validate_cracked(expected_hashes, allowed_passwords):
    assert os.path.isfile(JSON_PATH), f"File {JSON_PATH} is missing. The script did not generate the output."
    with open(JSON_PATH, "r") as f:
        try:
            cracked = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {JSON_PATH} is not valid JSON.")

    assert isinstance(cracked, dict), "cracked.json must contain a JSON object (dictionary)."
    assert len(cracked) > 0, "cracked.json is empty. No hashes were cracked."
    assert set(cracked) == set(expected_hashes), (
        "cracked.json must contain every supplied legacy hash and no substituted hashes."
    )

    for h, p in cracked.items():
        assert h in expected_hashes, f"Hash {h} in cracked.json was not an original legacy hash."
        assert isinstance(p, str), f"Cracked password for {h} is not a string."
        assert p in allowed_passwords, f"Password for {h} was not read from the supplied wordlist."
        assert md5_crypt.verify(p, h), f"Password '{p}' does not correctly verify against hash {h}."
    return cracked


def test_audit_script_modified():
    """Check that the audit script no longer accepts passwords via CLI."""
    assert os.path.isfile(AUDIT_PATH), f"File {AUDIT_PATH} is missing."

    with open(AUDIT_PATH, "r") as f:
        content = f.read()

    assert "--passwords" not in content, "Audit script still contains '--passwords' CLI argument."
    assert "argparse" not in content or "add_argument('--passwords'" not in content, \
        "Audit script still accepts passwords via CLI."


def test_cracked_json_and_original_audit_execution():
    """Run the script and require correct cracks for every immutable original hash."""
    assert os.path.isfile(WORDLIST_PATH), f"File {WORDLIST_PATH} is missing."
    with open(WORDLIST_PATH, "r") as f:
        passwords = [line.rstrip("\r\n") for line in f if line.rstrip("\r\n")]
    assert passwords, "wordlist.txt must contain at least one password, one per line."

    with open(HASHES_PATH, "w") as f:
        f.write("\n".join(ORIGINAL_HASHES) + "\n")
    if os.path.exists(JSON_PATH):
        os.remove(JSON_PATH)

    _run_audit_without_password_argv(passwords)
    _load_and_validate_cracked(ORIGINAL_HASHES, passwords)


def test_audit_reads_wordlist_and_hash_file_at_runtime():
    """Exercise audit.py with verifier-generated hashes and passwords."""
    saved = {}
    for path in (HASHES_PATH, WORDLIST_PATH, JSON_PATH):
        saved[path] = open(path, "rb").read() if os.path.exists(path) else None

    token = secrets.token_hex(10)
    answers = [f"runtime_{token}_{i}" for i in range(3)]
    decoys = [f"decoy_{token}_{i}" for i in range(400)]
    wordlist = decoys[:137] + [answers[0]] + decoys[137:266] + [answers[1]] + decoys[266:] + [answers[2]]
    hashes = [md5_crypt.hash(password, salt=secrets.token_hex(4)) for password in answers]

    try:
        with open(WORDLIST_PATH, "w") as f:
            f.write("\n".join(wordlist) + "\n")
        with open(HASHES_PATH, "w") as f:
            f.write("\n".join(hashes) + "\n")
        if os.path.exists(JSON_PATH):
            os.remove(JSON_PATH)

        _run_audit_without_password_argv(wordlist)
        cracked = _load_and_validate_cracked(hashes, wordlist)
        assert cracked == dict(zip(hashes, answers)), "audit.py returned incorrect runtime-derived cracks."
    finally:
        for path, data in saved.items():
            if data is None:
                try:
                    os.remove(path)
                except FileNotFoundError:
                    pass
            else:
                with open(path, "wb") as f:
                    f.write(data)


def test_speedup_metric():
    """Check the execution speedup of md5_crypt.verify() against the baseline."""
    setup_code = "from passlib.hash import md5_crypt; h = md5_crypt.hash('secret')"
    test_code = "md5_crypt.verify('secret', h)"

    try:
        new_time = timeit.timeit(test_code, setup=setup_code, number=50)
    except Exception as e:
        pytest.fail(f"Failed to benchmark md5_crypt.verify: {e}")

    baseline_time = 2.5
    speedup = baseline_time / new_time

    assert speedup >= 20.0, (
        f"Performance bottleneck not fully resolved. "
        f"Achieved speedup: {speedup:.2f}x (Threshold >= 20.0x). "
        f"Time taken for 50 iterations: {new_time:.4f}s."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
